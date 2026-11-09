# Facteur

Facteur is a Rails engine that logs every email your app sends in a `facteur_mailings` table, delivers it
through Sidekiq (never twice), and tracks what happens to it afterwards through the webhooks of the mail
provider (SendGrid or Scaleway Transactional Email).

## Installation

```ruby
# Gemfile
gem 'facteur', git: 'https://github.com/tbdsoftware/facteur'
```

```ruby
# config/routes.rb
mount Facteur::Engine => '/facteur'
```

```sh
bin/rails g facteur:active_record
bin/rails db:migrate
```

The generator copies the migrations your app does not have yet (`create_facteur_mailings`,
`add_tracking_to_facteur_mailings`), so an app already using Facteur can run it again to get only the new
ones. PostgreSQL is required (`jsonb` columns).

Mailings are created with `Facteur::Mailing.create!` (or `create_if_unsent!` to never send the same mail twice)
and delivered by `Facteur::MailingDeliveryJob`. Include `Facteur::DeviseFacteurable` in a Devise model to send
Devise notifications through Facteur.

## Upgrading (e.g. Hamelin)

1. Run `bin/rails g facteur:active_record` and `bin/rails db:migrate` **before** deploying the new code:
   `compute_status` reads `skipped_at` on every save, so `Facteur::Mailing.create!` fails until the
   `add_tracking_to_facteur_mailings` columns exist. The migration only adds 3 columns (the `jsonb` default is
   metadata-only on PostgreSQL 11+, no backfill, no long lock).
2. Apps sending through Scaleway must set `config.provider = :scaleway`: the default `:sendgrid` now adds
   `X-SMTPAPI` in every environment, production included.

## Configuration

```ruby
# config/initializers/facteur.rb
Facteur.configure do |config|
  config.provider = :scaleway # :sendgrid (default) or :scaleway
  config.scaleway_webhook_token = Rails.application.credentials.dig(:facteur, :scaleway_webhook_token)
end
```

- Every mail gets an `X-Facteur-Mailing-Id: <mailing id>` header, whatever the provider.
- `X-SMTPAPI` (SendGrid unique args) is only added when `provider` is `:sendgrid`, in every environment.
- Without `scaleway_webhook_token`, the Scaleway endpoint always answers 404. Use a long random value
  (`SecureRandom.hex(32)`).

## Webhooks

| Provider | Endpoint |
| --- | --- |
| SendGrid | `POST /facteur/sendgrid` |
| Scaleway TEM | `POST /facteur/scaleway/<scaleway_webhook_token>` |

The webhooks controller inherits `ActionController::API`, not your `ApplicationController`, so your
authentication filters do not apply to it.

The Scaleway endpoint:

1. answers 404 when the token is missing or wrong, and does nothing else;
2. reads the raw body (SNS posts JSON as `text/plain`), 400 when it is not a JSON object;
3. verifies the SNS signature (SignatureVersion 1 = SHA1, 2 = SHA256) with the certificate of
   `SigningCertURL`, downloaded only from `https://messaging.s3.<region>.scw.cloud` and cached per process;
   403 when invalid;
4. `SubscriptionConfirmation`: visits `SubscribeURL` when it is `https://sns.mnq.<region>.scaleway.com`,
   otherwise logs it so you can confirm the subscription by hand;
   `Notification`: enqueues `Facteur::MailProviderHookJob` with the TEM payload. Answers 200.

Events are attached to their mailing through the `X-Facteur-Mailing-Id` header found in the TEM
`email_headers` (key compared case-insensitively). Events without a matching mailing are logged and ignored.
An event already recorded (same provider event id) is ignored, so SNS redeliveries are harmless.

## Scaleway setup

> The token is part of the URL path, so it appears in your host's request logs: keep those logs private and
> rotate the token (credentials + subscription) if they leak.

1. **Topic**: in the Scaleway console, Topics and Events, activate SNS in the project and region of the TEM
   domain (e.g. `fr-par`), create SNS credentials with `can_manage` **and** `can_receive` (both are needed to
   subscribe an URL), then create a topic, e.g. `facteur-tem`.
2. **Subscription**: subscribe `https://<your host>/facteur/scaleway/<token>` to the topic with the HTTPS
   protocol, from the console or with the AWS CLI and the SNS credentials:

   ```sh
   aws sns subscribe --endpoint-url https://sns.mnq.fr-par.scaleway.com --region fr-par \
     --topic-arn <topic arn> --protocol https \
     --notification-endpoint https://<your host>/facteur/scaleway/<token>
   ```

   Facteur confirms the subscription by itself; check that it shows as confirmed. If not, the log contains the
   `SubscribeURL` to paste in the console (Topics and Events > Confirm subscription).
3. **TEM webhook**: the Essential plan allows only **one webhook per domain**, so a single webhook must carry
   every event type:

   ```sh
   scw tem webhook create domain-id=<domain id> name=facteur sns-arn=<topic arn> \
     event-types.0=email_queued event-types.1=email_delivered event-types.2=email_deferred \
     event-types.3=email_dropped event-types.4=email_spam event-types.5=email_mailbox_not_found \
     event-types.6=email_blocklisted region=fr-par
   ```

   Repeat for each sending domain.

## Statuses

| Event | Effect on the mailing |
| --- | --- |
| TEM `email_queued`, SendGrid `processed` | `processed_at` → `processed` |
| TEM `email_delivered`, SendGrid `delivered` | `delivered_at` → `delivered` |
| TEM `email_deferred`, SendGrid `deferred` | recorded, status unchanged (temporary failure) |
| SendGrid `open` / `click` | `opened_at` / `clicked_at` → `opened` / `clicked` |
| TEM `email_dropped`, `email_spam`, `email_mailbox_not_found`, `email_blocklisted` | `error_at` + `error_msg` (`<type>: <reason>`) → `error` |
| SendGrid `dropped`, `bounce`, `spamreport` | `error_at` + `error_msg` → `error` |
| Permanent SMTP refusal (5xx) at delivery | `error_msg` = `smtp_rejected: <SMTP response>` → `error`, not retried |
| Other TEM events (e.g. `blocklist_created`) | ignored |

Scaleway sends a generic `email_dropped` next to a more specific error (e.g. `email_mailbox_not_found`); it is
left out of `error_msg` when a more specific error exists. Temporary SMTP errors (4xx, timeouts, network)
raise so that Sidekiq retries.

### Skip reasons

A mailing that is never sent gets the `skipped` status, a `skipped_at` date and a `skip_reason`:

| `skip_reason` | Why |
| --- | --- |
| `expired` | the delivery ran more than one day after the mailing was created (e.g. after a Sidekiq outage) |
| `skipped` | the mailer's `should_skip_facteur_mailing?(mailing)` returned true |
| `blocked_recipient` | blank recipient or `@example.com` address |
| `suppressed` | reserved for a future suppression list, not used yet |

## Manual end-to-end test with Scaleway

The specs replay real payloads captured on 09/11/2026 (`spec/fixtures/scaleway`). Run this procedure again
if Scaleway changes its format, and refresh the fixtures with what you receive.

1. Start a local receiver that logs the raw requests, e.g. the dummy app
   (`cd spec/dummy && FACTEUR_SCALEWAY_TOKEN=<token> FACTEUR_INLINE_JOBS=1 bin/rails server -p 3000`, see
   below) or any small HTTP server, and expose it with `ngrok http 3000`.
2. Subscribe `https://<ngrok host>/facteur/scaleway/<token>` to a test topic (see Scaleway setup) and check the
   subscription is confirmed.
3. Create a temporary TEM webhook on the domain with every event type, pointing to the test topic.
   Keep it about 5 minutes only: meanwhile every event of the domain goes to the test topic. The Essential plan
   allows one webhook per domain, so if the domain already has one, the production webhook must be removed
   during the test and recreated afterwards.
4. Send test mails through Scaleway SMTP with an `X-Facteur-Mailing-Id: test-<n>` header: a real address, a
   non-existent mailbox (e.g. a random gmail address), a domain without MX, a syntactically invalid address
   (refused immediately with `501 5.1.3`).
5. Save the received envelopes (keep at least one untouched, with the certificate of its `SigningCertURL`, for
   the signature spec; mask personal addresses in the others).
6. Delete the TEM webhook and the subscription (`scw tem webhook delete <id>`).

## Development

Requirements: Ruby 3.4, PostgreSQL. No Redis: specs use `Sidekiq::Testing`.

```sh
bundle install
cd spec/dummy && RAILS_ENV=test bin/rails db:create db:schema:load && cd ../..
bundle exec rspec
```

The databases default to `postgres://localhost/facteur_test` and `postgres://localhost/facteur_development`;
set `DATABASE_URL` to use another one.

The dummy app can run as a server to try the webhooks by hand:

```sh
cd spec/dummy
bin/rails db:prepare
FACTEUR_SCALEWAY_TOKEN=secret FACTEUR_PROVIDER=scaleway FACTEUR_INLINE_JOBS=1 bin/rails server -p 3000
```

- `FACTEUR_SCALEWAY_TOKEN`: token of `POST /facteur/scaleway/<token>` (404 when unset);
- `FACTEUR_PROVIDER`: `sendgrid` (default) or `scaleway`;
- `FACTEUR_INLINE_JOBS=1`: runs Sidekiq jobs inline, without Redis.

Mails are delivered with the `:test` delivery method, logs go to `spec/dummy/log/development.log`.
