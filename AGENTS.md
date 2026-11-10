# AGENTS.md

TBDS coding conventions: rules for all code, the Rails backend and deployment. SvelteKit apps have their own `AGENTS.md` in their folder.

This file is copied from `tbdsoftware/tbds-conventions` by its `apply.sh`: never edit it here, change `tbds-conventions` and re-apply. Project-specific context and deviations belong in the project's `CLAUDE.md` (which imports this file with `@AGENTS.md`) and win where the two disagree.

## Default stack

- **Backend**: Rails 8, API-only (`config.api_only = true`), Postgres. JSON is rendered with the **`jb`** gem (`app/views/**/*.json.jb`), not Jbuilder. Devise + devise-jwt for auth. `ransack` for filterable search. Sidekiq + sidekiq-cron for background jobs.
- **Frontend**: SvelteKit 2 / Svelte 5, TypeScript, Tailwind CSS 4, plain `flowbite` markup with its v4 semantic tokens (never `flowbite-svelte`, never Flowbite's JS). See the app's own `AGENTS.md`.
- **Deployment**: Kubernetes on the shared TBDS cluster (Scaleway Kapsule `k8s-tbds`, `fr-par`), GitHub Actions for CI/CD. Not Kamal.
- **Lint**: RuboCop with `rubocop-rails-omakase` + the TBDS house rules and `Tbds/*` cops (`.tbds/rubocop.yml`).

## All code

### Language

Write all code in English: identifiers, comments, commit messages, and route folder names (i.e. URL path segments), on both backend and frontend, even though the products are French. Exceptions: user-facing strings that are intentionally French (e.g. `messages/fr.json`), and French domain terms used as proper nouns (Pinel, Malraux, Denormandie…).

### Comments

Keep comments to a minimum, defaulting to none, anywhere. Well-named identifiers and small functions/files make the *what* self-evident; only comment a *why* that isn't obvious from the code (a non-obvious constraint, a workaround for a specific bug or library quirk, an invariant a future edit could easily break). Don't narrate what the next line does, and don't restate what something visibly already is (a `// trash icon` above a constant named `trashIcon`). If deleting a comment would leave a future reader no worse off, don't write it.

## Rails backend

### Ruby style

- No comment on a method, ever. A class gets at most a 1–2 line comment, only for a genuine *why*.
- Prefer `.blank?`/`.present?` over `.nil?` (keep `.nil?` only where `blank?` would change the semantics, e.g. `""` must stay valid).
- Name a variable after its class: `lot = Lot.find(...)`, `publish_blobs_service = PublishBlobsService.new(...)`, not `service`/`obj`/`x`.
- Prefer `if` (negating the condition if needed) over `unless`.

### Thin models and controllers, business logic in services

- **A model is data only**: columns, associations, enums, scopes, callbacks, validations, and derived attributes computed purely from that model's own columns with no judgment call baked in (e.g. `address_full` = `[address, city, postal_code].compact.join(", ")`).
- **No class methods on models** (`def self.x`, `class << self`), except those a framework requires (e.g. Ransack's `ransackable_attributes`). Scopes are fine for plain query filters, never for business rules.
- **All business logic lives in `app/services/`**, called from the **controller** action that needs it, not from a model method and not inlined in the controller. As soon as logic encodes a *rule* (a convention, a policy, a "this means that" decision, even one that reads a single column), reaches across several models, or orchestrates a multi-step side effect, it's a service. Example: "a tag whose name starts with `region-` restricts program visibility" only reads `Tag#name`, but it's a Program visibility rule, so it's `Program::RestrictVisibilityService`, not `Tag#restricts_program_visibility?`.
- **Controllers only permit params and call a service or `save`.** Form objects are allowed for multi-model or param-heavy input (`app/forms/`).
- **One service per operation**, invoked as `Klass.new(...).call`, never a bag of class methods on a `<Model>Service`. A service centered on a model is namespaced under it, `Model::VerbNounService` (`app/services/program/filter_visible_service.rb` → `Program::FilterVisibleService.new(scope, user, promoter).call`); a use case that doesn't center on one model keeps a flat name (`PublishBlobsService`).
- **A service exposes nothing but `initialize` and `call`.** `initialize` takes every input; `call` takes no arguments and returns the result: the domain record(s) it worked on, or a plain boolean for a predicate. No class methods, no public `attr_*` readers to read state back afterward. `Tbds/ServiceSinglePublicMethod` flags extra public methods and class methods.
- **Report failure the Rails way**, through the returned records' `errors`, like `save`. No `Result`/`Success`/`Failure` objects.
- **A job only delegates to its namesake service**: `CrmSync::SyncPromoterExternalSourcesJob#perform` calls `CrmSync::SyncPromoterExternalSourcesService.new(...).call` and holds no logic of its own (`Tbds/JobServiceNaming`).
- `app/models/` holds ActiveRecord-backed classes only. Any other plain Ruby class (adapters, registries, synchronizers) goes in `app/services/` too.
- Service specs live in `spec/services/`, not folded into a model or controller spec.

### API surface

- Two versioned namespaces, compact class form matching the directory depth (`class Api::Management::V1::LotsController < Api::Management::V1::BaseController`, not nested `module` blocks):
  - **`Api::Management::V1::*`**: admin CRUD, JWT-protected via Devise + devise-jwt (JTI revocation). The JWT travels in the `Authorization` header, not Devise's HTML flow.
  - **`Api::Public::V1::*`**: client-facing (showcase sites), authenticated by an `X-Api-Key` header that also identifies the tenant the request is scoped to; skips `authenticate_user!`.
- **Keep controllers minimal, one purpose each.** Small dedicated lookups that aren't a resource listing (e.g. a distinct list of cities) go into a `SearchController` per namespace rather than being bolted onto another endpoint.
- JSON views are `.json.jb` files. Don't add `.jbuilder` files.
- **Each action renders its own view** (`presign` → `presign.json.jb`, or `render :show` after a create/update), never another controller's template (`render "api/uploads/presign"`, `render template: ...`). JSON shared between endpoints goes in a partial that each view renders. Enforced by `Tbds/RenderOwnView` in `app/controllers/**`.
- `swagger/v1/swagger.yaml` is **hand-maintained**, even with `rswag` in the Gemfile. Don't run `rswag:specs:swaggerize`: it overwrites the file with only the paths covered by rswag-DSL specs. After changing an endpoint's request/response shape, edit the YAML directly; the frontend regenerates its types from it.

### Slugs, never raw ids in URLs

- Every record that gets its own URL or nested management-API path has a `slug` column via FriendlyId (`friendly_id <source_column>, use: [:slugged, :scoped], scope: <parent_id>`), generated once from a human-readable column and never regenerated on rename.
- Uniqueness is per parent: a composite unique index (`(parent_id, slug)`), not a bare `slug` index. Only top-level records (no parent) get a plain unique index on `slug`.
- Records with no unique human-readable name and no page of their own (e.g. uploaded media, memberships) may keep their numeric id; they're still looked up through their parent association.
- Controllers resolve slugs **through the already-scoped parent association** (`current_promoter.programs.friendly.find(params[:id])`), never on the bare class (`Program.friendly.find(...)` ignores the scope). Top-level records are the exception. Enforced by the `Tbds/ScopedFind` cop in `app/controllers/api/management/**` (project-specific exceptions go in the project's `.rubocop.yml`).

### Data, time and migrations

Each rule here is enforced by a `Tbds/*` cop. For a legacy offense that can't be fixed (e.g. a migration already run everywhere), exclude that exact file in the project's `.rubocop.yml` or disable the cop on that exact line; never exclude a whole folder.

- **Enums** store string values (`{ active: "active" }`, never integers) and always declare `prefix:` or `suffix:`, so their generated predicates and scopes can't clash.
- **Time**: never `to_time` (it ignores the app time zone), use `in_time_zone`. Never `strftime`: use `I18n.l` for display, `iso8601` in API payloads.
- **Errors**: never `rescue StandardError`; rescue the specific exception you expect.
- **Callback-skipping writes** (`update_all`, `update_columns`, `update_column`) must set `updated_at` themselves (`updated_at: Time.current`). Migrations and specs are exempt.
- **JSONB**: query with `col -> 'a' ->> 'b'`, never `#>` / `#>>`, which don't match expression indexes.
- **Mailers** take their arguments through `with`: `UserMailer.with(user_id: id).welcome_email`, not `UserMailer.welcome_email(id)`.
- **Migrations**:
  - Always generate them with `bin/rails generate migration`; a hand-written timestamp (ending in `0000`) breaks their real order across branches.
  - datetime/timestamp columns end in `_at`, date columns in `_on`.
  - With `disable_ddl_transaction!`, keep a single statement per `up` / `down` / `change`.

### Schema dump and model annotations

- `db/schema.rb` (or `db/structure.sql`) and the schema block at the bottom of each model are generated: `db:migrate` rewrites both in development (annotaterb, through `lib/tasks/annotate_rb.rake`). Commit them as generated, never edit them by hand.
- CI's `.tbds/bin/check_db_schema` fails when a branch's migrations, run on its base branch's seeded schema, don't produce exactly the committed dump and annotations, or when a new migration doesn't roll back (unless it raises `ActiveRecord::IrreversibleMigration`).

### Naming (Zeitwerk)

- The file path must match the constant it defines exactly. One class/module per file, and a namespaced class needs the matching directory nesting.
- Controllers: plural resource + `Controller`. Models: singular CamelCase for a plural snake_case table (cross-check irregular nouns against `db/schema.rb`).
- Acronyms follow Zeitwerk's default inflection: `Api`, `Jwt`, `Crm`, not `API`. If an acronym is genuinely needed, add `inflect.acronym` in `config/initializers/inflections.rb` rather than spelling the class differently from its filename.
- Before considering a new or renamed file done: `bin/rails zeitwerk:check` and `bin/rubocop <path>`.

### Ops scripts

One-off database operations (locally or against a deployed environment) are rake tasks in `lib/tasks/admin.rake`, not ad-hoc `rails console` sessions or raw SQL: `task :name, [ :arg1, :arg2 ] => :environment do |_task, args| ... end`, invoked as `bin/rails "admin:name[arg1,arg2]"` (quoted, since shells glob `[`/`]`). Make them idempotent (`find_or_initialize_by`). Against a deployed backend: `kubectl exec deployment/<backend-deployment> -- bin/rails "admin:<task>[args]"`, which reuses the pod's already-injected secrets.

## Deployment (Kubernetes)

- Each app has its own GitHub Actions pipeline: build the Docker image, push it to Scaleway Container Registry, run pending migrations through a one-off `kubectl` Job (backend), then `kubectl set image` on the existing Deployment.
- **CD only ever bumps the image tag (`kubectl set image`). It never `kubectl apply`s the Deployment/Service/Ingress manifests.** The manifests under `deployment/` are the source of truth for the spec, but applying them is a one-off manual step per environment. **If you edit a manifest, run `kubectl apply -f <that file>` yourself after merging**, or the cluster silently keeps the old spec. This is deliberate: an automatic apply would revert manual incident fixes and widen every push's blast radius to the whole spec.
- `spec.selector.matchLabels` is immutable on an existing Deployment: match the live value exactly, or delete and recreate the Deployment.
- Runtime secrets come from a Kubernetes Secret, never through GitHub Actions.
- **Developers' kubeconfigs hold contexts for several clients' clusters. Always run `kubectl config current-context` before any `kubectl` command** and confirm it's the TBDS cluster (named `admin@k8s-tbds` or `k8s-tbds-<id>` depending on the machine). `kubectl` never asks for confirmation.
