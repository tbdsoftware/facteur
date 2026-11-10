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
`add_tracking_to_facteur_mailings`, `filter_tokens_in_facteur_mailings`), so an app already using Facteur can run
it again to get only the new ones. PostgreSQL is required (`jsonb` columns).

Mailings are created with `Facteur::Mailing.create!` (or `Facteur::Mailing::CreateIfUnsentService.new(attributes).call`
to never send the same mail twice) and delivered by `Facteur::MailingDeliveryJob`. Include `Facteur::DeviseFacteurable` in a Devise model to send
Devise notifications through Facteur.

## Upgrading (e.g. Hamelin)

Facteur requires Rails >= 7.0 (it uses the positional `enum :status, { ... }` syntax) and is tested on
Rails 7.1, 7.2 and 8.0.

1. Run `bin/rails g facteur:active_record` and `bin/rails db:migrate` **before** deploying the new code:
   `compute_status` reads `skipped_at` on every save, so `Facteur::Mailing.create!` fails until the
   `add_tracking_to_facteur_mailings` columns exist. The migration only adds 3 columns (the `jsonb` default is
   metadata-only on PostgreSQL 11+, no backfill, no long lock).
2. Apps sending through Scaleway must set `config.provider = :scaleway`: the default `:sendgrid` now adds
   `X-SMTPAPI` in every environment, production included.

## Upgrading to 0.4.0

0.4.0 secures the webhooks and the stored mails. Before deploying it:

1. Run `bin/rails g facteur:active_record` and `bin/rails db:migrate`. The new `filter_tokens_in_facteur_mailings`
   migration only changes data: it replaces the Devise tokens of the stored mails with `[FILTERED]` (see
   [Stored mails](#stored-mails)). It updates the whole table with a regular expression (sequential scan): on a
   large table, run it at a quiet time. It cannot be rolled back (its `down` restores nothing).
2. Only the webhook of the configured `provider` keeps its route, unless you list them in `config.webhooks`: a
   webhook missing from it answers 404.
3. **SendGrid apps**: enable the Signed Event Webhook in SendGrid (Settings > Mail Settings > Event Webhook >
   Signature verification) and set `config.sendgrid_webhook_public_key` to the public key it shows. Without it,
   `POST /facteur/sendgrid` answers 403 and every event is lost.
4. **Scaleway apps**: set `config.scaleway_topic_arns` to the ARN of your topic (every message is refused with a
   403 while it is empty). The token moves from the path to the query string: subscribe
   `https://<your host>/facteur/scaleway?facteur_token=<token>` to the topic (see [Scaleway setup](#scaleway-setup)),
   check it is confirmed, then delete the subscription to the old `https://<your host>/facteur/scaleway/<token>`
   URL, which now answers 404.

## Upgrading to 0.3.0

The engine code moved to `app/` and `Facteur::Mailing` now only holds data. The table, the `status` enum and its
scopes, the `sent`/`processed`/… scopes and predicates, the job class names, the webhooks and
`Facteur::DeviseFacteurable` are unchanged.

`Facteur::Mailing`, `Facteur::DeviseFacteurable`, the jobs and the services are now autoloaded from the engine's
`app/` folders (only `Facteur.configure` and `Facteur::Engine` load with the gem): host code must not reference
them while the app boots, e.g. in an initializer wrap such code in `Rails.application.config.to_prepare do … end`.

These public methods were removed:

| Removed | Use instead |
| --- | --- |
| `Facteur::Mailing.create_if_unsent!(attributes)`, `#sent_mailings` | `Facteur::Mailing::CreateIfUnsentService.new(attributes).call` |
| `#deliver`, `#inner_deliver`, `#skip!`, `#compute_mail_headers`, `#compute_mail_fields`, `#should_skip?`, `#will_be_blocked?`, `#mailer` | `Facteur::MailingDeliveryService.new(mailing).call` (or `Facteur::MailingDeliveryJob`) |
| `#compute_mail`, `#prospect_demo_user?` | nothing: they were unused |
| `.pending`, `.not_pending`, `#pending?` | `.current_status_pending` / `#current_status_pending?` (there is no `pending_at` column: they never worked) |
| `#status_class`, `Facteur::ApplicationRecordable` (`#human_enum_name`, `.collection_from_enum_with_ivalues`, …) | your own helpers; the ActiveAdmin page keeps the same labels, colours and filter |
| `Facteur::Scaleway::SnsCertificateCache` | nothing: the certificate cache is internal to `Facteur::Scaleway::VerifySnsSignatureService` |

## Configuration

An app sending through Scaleway (e.g. Hamelin):

```ruby
# config/initializers/facteur.rb
Facteur.configure do |config|
  config.provider = :scaleway
  config.webhooks = %i[scaleway]
  config.scaleway_webhook_token = Rails.application.credentials.dig(:facteur, :scaleway_webhook_token)
  config.scaleway_topic_arns = ['arn:scw:sns:fr-par:project-<project id>:facteur-tem']
end
```

An app sending through SendGrid:

```ruby
Facteur.configure do |config|
  config.provider = :sendgrid
  config.sendgrid_webhook_public_key = Rails.application.credentials.dig(:facteur, :sendgrid_webhook_public_key)
end
```

| Option | Default | |
| --- | --- | --- |
| `provider` | `:sendgrid` | `:sendgrid` or `:scaleway`, the provider the mails go through |
| `webhooks` | `nil` | webhooks whose route is drawn (symbols or strings), e.g. `%i[scaleway]`; `nil` = only the `provider`'s |
| `sendgrid_webhook_public_key` | `nil` | public key of SendGrid's Signed Event Webhook (base64, as SendGrid shows it) |
| `scaleway_webhook_token` | `nil` | secret expected in the `facteur_token` query parameter of the Scaleway webhook |
| `scaleway_topic_arns` | `[]` | SNS topics the Scaleway webhook accepts messages from |
| `store_body` | `true` | `false` never stores the mail bodies |

- Every mail gets an `X-Facteur-Mailing-Id: <mailing id>` header, whatever the provider.
- `X-SMTPAPI` (SendGrid unique args) is only added when `provider` is `:sendgrid`, in every environment.
- Without `scaleway_webhook_token`, the Scaleway endpoint always answers 404. Use a long random value
  (`SecureRandom.hex(32)`).
- The routes are drawn when the app loads its routes, after the initializers: set `webhooks` in an initializer.

## Webhooks

| Provider | Endpoint | Drawn when |
| --- | --- | --- |
| SendGrid | `POST /facteur/sendgrid` | `:sendgrid` is in `webhooks` (or is the `provider` when `webhooks` is not set) |
| Scaleway TEM | `POST /facteur/scaleway?facteur_token=<scaleway_webhook_token>` | `:scaleway` is in `webhooks` (or is the `provider` when `webhooks` is not set) |

The webhooks controller inherits `ActionController::API`, not your `ApplicationController`, so your
authentication filters do not apply to it. Both endpoints answer 413 to a body over 1 MB.

The SendGrid endpoint:

1. answers 403 (and logs an error) when `sendgrid_webhook_public_key` is not set;
2. verifies the ECDSA signature of the raw body (`X-Twilio-Email-Event-Webhook-Signature` and
   `X-Twilio-Email-Event-Webhook-Timestamp` headers) with that key, 403 when missing or invalid;
3. answers 400 when the body is not a JSON array of objects, 413 over 5 000 events;
4. enqueues `Facteur::MailProviderHookJob` with the events. Answers 200.

The Scaleway endpoint:

1. answers 404 when the `facteur_token` query parameter is missing or wrong, and does nothing else;
2. reads the raw body (SNS posts JSON as `text/plain`), 400 when it is not a JSON object;
3. answers 403 when its `TopicArn` is not in `scaleway_topic_arns` (every message when the list is empty),
   before downloading anything;
4. verifies the SNS signature (SignatureVersion 1 = SHA1, 2 = SHA256), 403 when invalid. The certificate must
   come from `https://messaging.s3.<region>.scw.cloud/<region>/sns/sns_certificate_<hex>.pem` (`<region>` among
   `fr-par`, `nl-ams`, `pl-waw`), be issued to `sns.mnq.<region>.scaleway.com` and be currently valid. Up to 10
   certificates are cached per process. Messages whose `Timestamp` is older than 6 hours or more than 5 minutes
   ahead are refused, so a captured message cannot be replayed later;
5. `SubscriptionConfirmation`: visits `SubscribeURL` when it is `https://sns.mnq.<region>.scaleway.com`,
   otherwise logs it so you can confirm the subscription by hand;
   `Notification`: enqueues `Facteur::MailProviderHookJob` with the TEM event when `Message` is a JSON object,
   otherwise logs and ignores it. Answers 200.

Events are attached to their mailing through the `X-Facteur-Mailing-Id` header found in the TEM
`email_headers` (key compared case-insensitively). Events without a matching mailing are logged and ignored.
An event already recorded (same provider event id) is ignored, so SNS redeliveries are harmless.

## Scaleway setup

> The engine adds `facteur_token` to your app's `filter_parameters`, so the Rails logs (and the tools that honour
> `filter_parameters`, e.g. lograge or Sentry) show `facteur_token=[FILTERED]`. Access logs of your ingress or
> proxy still contain the query string: keep them private and rotate the token (credentials + subscription) if
> they leak.

1. **Topic**: in the Scaleway console, Topics and Events, activate SNS in the project and region of the TEM
   domain (e.g. `fr-par`), create SNS credentials with `can_manage` **and** `can_receive` (both are needed to
   subscribe an URL), then create a topic, e.g. `facteur-tem`.
2. **Allow-list**: add the topic ARN to `scaleway_topic_arns` and deploy, otherwise the subscription confirmation
   itself is refused.
3. **Subscription**: subscribe `https://<your host>/facteur/scaleway?facteur_token=<token>` to the topic with the
   HTTPS protocol, from the console or with the AWS CLI and the SNS credentials:

   ```sh
   aws sns subscribe --endpoint-url https://sns.mnq.fr-par.scaleway.com --region fr-par \
     --topic-arn <topic arn> --protocol https \
     --notification-endpoint 'https://<your host>/facteur/scaleway?facteur_token=<token>'
   ```

   Facteur confirms the subscription by itself; check that it shows as confirmed. If not, the log contains the
   `SubscribeURL` to paste in the console (Topics and Events > Confirm subscription).
4. **TEM webhook**: the Essential plan allows only **one webhook per domain**, so a single webhook must carry
   every event type:

   ```sh
   scw tem webhook create domain-id=<domain id> name=facteur sns-arn=<topic arn> \
     event-types.0=email_queued event-types.1=email_delivered event-types.2=email_deferred \
     event-types.3=email_dropped event-types.4=email_spam event-types.5=email_mailbox_not_found \
     event-types.6=email_blocklisted region=fr-par
   ```

   Repeat for each sending domain.

## Stored mails

Each mailing stores its subject, sender, recipients and body (`body`), shown on the ActiveAdmin page in a
sandboxed iframe (the body is never evaluated, its scripts never run).

The value of the `reset_password_token`, `confirmation_token`, `unlock_token` and `invitation_token` URL
parameters is replaced with `[FILTERED]` before the body is stored, whatever the mailer (e.g. a welcome mail with
a password reset link). For the `reset_password_instructions`, `confirmation_instructions`, `unlock_instructions`
and `invitation_instructions` mailings, the token passed to the mailer (first element of `mailer_params`) is
replaced with `[FILTERED]` once the mailing is sent, skipped or refused by SMTP: until then a Sidekiq retry needs
it to build the mail again.

Set `config.store_body = false` to store no body at all.

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
   (`cd spec/dummy && FACTEUR_SCALEWAY_TOKEN=<token> FACTEUR_SCALEWAY_TOPIC_ARNS=<topic arn> FACTEUR_INLINE_JOBS=1
   bin/rails server -p 3000`, see below) or any small HTTP server, and expose it with `ngrok http 3000`.
2. Subscribe `https://<ngrok host>/facteur/scaleway?facteur_token=<token>` to a test topic (see Scaleway setup)
   and check the subscription is confirmed.
3. Create a temporary TEM webhook on the domain with every event type, pointing to the test topic.
   Keep it about 5 minutes only: meanwhile every event of the domain goes to the test topic. The Essential plan
   allows one webhook per domain, so if the domain already has one, the production webhook must be removed
   during the test and recreated afterwards.
4. Send test mails through Scaleway SMTP with an `X-Facteur-Mailing-Id: test-<n>` header: a real address, a
   non-existent mailbox (e.g. a random gmail address), a domain without MX, a syntactically invalid address
   (refused immediately with `501 5.1.3`).
5. Save the received envelopes (keep at least one untouched, with the certificate of its `SigningCertURL`, for
   the signature spec; mask personal addresses in the others). The specs travel to the date of the fixtures
   (`SnsHelpers::FIXTURES_TIME`), as messages older than 6 hours are refused: update it with the new ones.
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

The root `Gemfile` runs on Rails 7.1. The CI also runs the specs on Rails 7.2 and 8.0, each with its own
Gemfile and lockfile in `gemfiles/`. Deprecations raise in the specs.

```sh
BUNDLE_GEMFILE=$PWD/gemfiles/rails_8_0.gemfile bundle install
BUNDLE_GEMFILE=$PWD/gemfiles/rails_8_0.gemfile bundle exec rspec
```

The dummy app can run as a server to try the webhooks by hand:

```sh
cd spec/dummy
bin/rails db:prepare
FACTEUR_SCALEWAY_TOKEN=secret FACTEUR_SCALEWAY_TOPIC_ARNS=<topic arn> FACTEUR_PROVIDER=scaleway \
  FACTEUR_INLINE_JOBS=1 bin/rails server -p 3000
```

- `FACTEUR_PROVIDER`: `sendgrid` (default) or `scaleway`;
- `FACTEUR_WEBHOOKS`: comma-separated webhooks to draw (default `sendgrid,scaleway`);
- `FACTEUR_SENDGRID_PUBLIC_KEY`: SendGrid's Signed Event Webhook public key (`POST /facteur/sendgrid` answers 403
  when unset);
- `FACTEUR_SCALEWAY_TOKEN`: token of `POST /facteur/scaleway?facteur_token=<token>` (404 when unset);
- `FACTEUR_SCALEWAY_TOPIC_ARNS`: comma-separated topic ARNs accepted by the Scaleway webhook (every message is
  refused when unset);
- `FACTEUR_INLINE_JOBS=1`: runs Sidekiq jobs inline, without Redis.

Mails are delivered with the `:test` delivery method, logs go to `spec/dummy/log/development.log`.
