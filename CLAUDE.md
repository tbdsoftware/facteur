@AGENTS.md

# facteur

A Rails engine gem (`Facteur::Engine`, isolated namespace), not an API app: the "Default stack", "API surface", "Slugs" and "Deployment (Kubernetes)" sections of `AGENTS.md` don't apply. It logs every email a host app sends (`Facteur::Mailing`), delivers it through Sidekiq, and records SendGrid / Scaleway TEM webhook events.

- **Host app**: hamelin (Rails 7.1, moving to 7.2; Ruby 3.4.6, hence `.ruby-version`). Keep the public API stable: `Facteur::Mailing` (table, `status` enum, scopes), `Facteur.configure`, `Facteur::DeviseFacteurable`, the job classes, the webhook routes and the `facteur:active_record` generator. Removing a public method means a version bump and a line in the README's upgrade notes.
- **Specs**: `spec/dummy` is the host app. Set its database up once with `cd spec/dummy && RAILS_ENV=test bin/rails db:create db:schema:load`, then `bundle exec rspec`. CI runs them on Rails 7.1 (root `Gemfile`), 7.2 and 8.0 (`BUNDLE_GEMFILE=gemfiles/rails_7_2.gemfile` / `rails_8_0.gemfile`, each with its own lockfile), with deprecations raising. After a Gemfile change, `bundle install` with all three.
- **Lint**: `bin/rubocop` (CI runs it). New or moved files under `app/`: also `cd spec/dummy && RAILS_ENV=test bin/rails zeitwerk:check`.
- **Deliberate deviations from `AGENTS.md`**:
  - `Facteur::Mailing#status` stays an integer enum without prefix (`Tbds/EnumValueAsString` and `Tbds/EnumUsePrefixOrSuffix` are excluded for that file): string values need a migration in every host database, and a prefix would rename the methods and scopes hosts call.
  - `Facteur::MailingDeliveryJob` and `Facteur::MailProviderHookJob` keep their names: jobs already queued in Redis during a deploy must still run.
  - The event → dates / `error_msg` computation stays in `Facteur::Mailing` as a private `before_save` callback: it is derived only from the model's own `events` column, and any write to `events` must recompute it.
  - No `lib/tasks/annotate_rb.rake` and no `check_db_schema` CI job: an engine's rake tasks load into every host app, and the gem has no schema of its own (only the generator's migration templates).
- Commits and pull requests carry no Claude / AI attribution: no `Co-Authored-By` trailer, no "Generated with" footer.
