# Possible improvements

Cross-referenced against the top recurring complaints in Rails, Sinatra,
Hanami, and Roda over the last ~3-5 years (GitHub issues, blog posts,
HN/Reddit threads, conference talks). Each item notes which framework
faces the same pain or, conversely, which framework already solved it
in a way worth copying.

## Already strong (keep)

* Tree routing with `map` / `call` / `match` and `route.with_scope`
  (Roda-style cursor, no nav mutation)
* Plugin system with canonical layout (`loader.rb`, `load/`, `hammer/`,
  `mount/`) - better discoverability than Roda's flat plugin list
* Schema / type system (`lib/lux/schema`, `lib/lux/type`) - own flavor
  of the dry-rb territory Hanami occupies
* Policy proxy, `Lux.current` thread-local, JWT sessions
* Response API: `halt`, `etag`, `early_hints`, `send_file`, `auth`
* Exception logger with mountable viewer (Hanami / Sinatra miss this)
* API introspect + explorer with AGENTS.md emit (no other Ruby fw does
  this)
* Custom reloader that skips `Gem.path` - addresses the Rails
  "reload-degradation" complaint head-on
* **`rescue_from` at app and controller level** (`Lux::Application.rescue_from`,
  `Lux::Controller.rescue_from`) - granularity is there, per-class
  matching still worth verifying with a spec

## Recently landed

Items from prior revisions of this doc that have shipped. Kept here as
a deliberate record so the same idea doesn't get re-pitched.

* **`bin/lux routes`** - `lib/lux/application/lib/routes_dumper.rb` +
  `bin/cli/routes_hammer.rb`. Shadow-replays route callbacks against a
  recording instance; `-v` adds source locations.
* **`opt` DSL + class-level `params do`** on `Lux::Controller`
  (`lib/lux/controller/params_dsl.rb`). Both forms defer to
  `Lux::Schema::Define`; strict drop / coerce / require behavior.
* **i18n** - `plugins/locale` ships namespaced lookups, dynamic
  namespaces, before/after hooks, and a `t` helper auto-exposed in
  templates. Earlier revisions of this doc wrongly claimed "no i18n".
* **OpenAPI 3 + Postman emit** - `lib/lux/api/doc/openapi_schema.rb`
  and `postman_schema.rb`, exposed via `/<mount>/sys/openapi`,
  `/sys/postman`, `/sys/agents`. The unified `Lux::Schema` DSL pays
  off: API contract is generated, not maintained.
* **Health probe** - `/<mount>/sys/health` via `Lux::Api::SysApi`.
* **JSON content negotiation by default** - `params_dsl.rb:114` and
  `controller.rb:211` both detect `application/json` request body and
  flip the response content type. No opt-in.
* **Job retry + exponential backoff** - `plugins/job_runner` has
  `RETRY_BASE_WAIT` and `MAX_RETRIES`, 1.6x backoff per attempt.

## Critical

Every framework gets burned here. lux-fw still missing or thin.

* **CSRF protection.** Grep finds nothing. Roda and Sinatra both
  criticized for opt-in CSRF. Needs first-class default-on for HTML
  form submissions (skip for JSON + Bearer). Helper should reuse the
  session + `Lux::Utils::Crypt` already in the framework.
* **CORS.** No plugin, no controller helper. Required the moment the
  API serves a browser SPA, and per-route policy means it can't fully
  live at the proxy. A thin `Lux.cors do origins ... end` fits the
  framework idiom better than dragging in `rack-cors`.
* **WebSocket / SSE / streaming primitive.** `Lux::Response` exposes
  `early_hints`, `etag`, `send_file` but no `stream` / `sse` / hijack.
  Sinatra and Roda need plugins, Rails has ActionCable.
  `response.stream { |s| ... }` or `response.sse` would be ~50 LOC and
  a real differentiator given the Rack-clean stack.

## High

Top-three complaint in at least one framework.

* **Mailer previews.** Rails has it, everyone else is jealous.
  `lib/lux/mailer` is solid but no `/sys/mailer_previews` route. Pair
  cleanly with the existing `/sys` namespace.
* **Form to schema error feedback loop.** `plugins/html` exists but no
  auto-binding from a form input to its schema error - the unified
  DSL makes this almost free (Hanami uses dry-validation for the same
  effect with more ceremony). A `form_for(schema)` builder that reads
  `Lux::Current.errors` would be the highest-leverage UI win.
* **Dev error page context.** `Lux::Error.render` shows status,
  message, and backtrace - no request body, no params, no source
  snippet around the failing line. Roda's #1 complaint is exactly
  this. The data is on `Lux.current`; rendering it in dev is mostly
  HtmlTag plumbing.
* **Request ID / correlation ID.** No `X-Request-Id` propagation, no
  `Lux.current.request_id`. Without it, structured logs across web +
  jobs + outbound HTTP can't be correlated. One-liner middleware, but
  has to exist before observability is useful.
* **Generators are thin.** `bin/cli/generate_hammer.rb` only reads
  `config/templates/*` and writes files interactively. Expand to a
  real scaffold: `lux generate resource User` emits controller +
  spec + route + schema + admin view in one shot, opinionated about
  the unified DSL.
* **Hot-reload edge cases.** The Rails complaint #1 is reloader
  breakage with custom containers / subclasses. AGENTS guide
  documents `load`-based reopen + "methods removed from source
  linger" - verify with a spec that `Lux::*` constant redefinition,
  plugin reload, and controller subclassing all survive.

## Medium

Recurring but lower frequency.

* **Dependency injection / slices.** Hanami's bounded-context story.
  lux has plugins but no per-mount isolated container. Probably not
  worth copying wholesale - flag, do not chase.
* **Job runner UX.** Retry + backoff are in. Verify dead-letter
  handling and surface a Sidekiq-Web equivalent through `admin_web`
  (the `lux mount job_runner` views are the seed).
* **Async / Falcon / fiber-friendly.** Rails finally got it. lux uses
  `Lux.defer` threads; fiber-safe `Lux.current` would future-proof.
* **File upload primitive.** No abstraction over multipart - host
  apps reinvent S3 PUT every time. A `Lux::Upload` with signed-URL
  generation, local-disk dev fallback, and a `:file` schema type
  would close the gap without ActiveStorage scope creep.
* **`Mailer.deliver_later`.** `plugins/job_runner` and `lib/lux/mailer`
  exist independently. Wire them so `UserMailer.welcome(u).deliver_later`
  enqueues via `LuxJob`. Today every app rolls its own.
* **Pagination.** No `paginate` helper on Sequel datasets nor a
  response convention. Universally needed; ~20 LOC on top of Sequel.
* **Webhook ingest primitive.** Signature verification
  (Stripe/GitHub/Slack style), idempotency keys, replay protection.
  No framework ships it - being first is a differentiator.
* **Encrypted credentials.** `Lux::Utils::Crypt` is here; surface it
  as a credentials store (`config/credentials.enc.yaml` decrypted at
  boot) and a Sequel column plugin.
* **Time / clock injection.** No `Lux.clock` / `Lux.now`. Tests that
  touch time pull Timecop. 30 LOC would drop that dependency.
* **Dev console with request replay.** `bin/lux console` exists but
  no "replay last request" affordance. Hanami and Rails both have it.
* **Test helpers shipping with framework.** Specs live under
  `spec/lux_tests/` but there's no `Lux::Spec::Request` for host apps
  to consume. Would help adoption.
* **Structured (JSON) logger mode.** Verify `plugins/lux_logger`
  emits JSON keyed by request ID for prod log shipping.

## Low

Nice-to-have, structural, or not our problem.

* **Static types (Sorbet / RBS).** Ruby-wide problem. Schema/type
  system already covers runtime; shipping RBS files for the public
  surface would be a polish item.
* **Asset pipeline depth.** `plugins/assets/cdn_asset` is enough for
  the lux philosophy; do not chase Sprockets / Propshaft.
* **Multi-DB ergonomics.** Already covered via `Lux.db(:name)` -
  arguably better than Rails.
* **HTTP outbound client wrapper.** Every app pulls Faraday/HTTP.rb
  separately. A thin `Lux.http` with timeouts + retries + structured
  logging would match the "batteries where it matters" stance.
* **OAuth provider mode.** `plugins/oauth` is consumer-side. Provider
  side is a big scope - flag, don't chase.
* **GraphQL.** Skip. The API + schema story already covers 90% of
  the use case with less ceremony.
* **Admin UI generator.** `plugins/admin_web` exists; an
  `lux generate admin_resource User` that emits a CRUD page would
  multiply its value.
* **Onboarding docs.** README + AGENTS.md combo is ahead of Roda and
  Hanami; just keep filling holes.

## Intentionally out of scope

Things people will ask for that the framework deliberately does not
own. Pitched, considered, declined - kept here so they don't get
re-pitched.

* **Rate limiting.** Belongs at the edge (nginx, Cloudflare, ALB) for
  IP/coarse limits, or as a per-route before-filter using `Lux.cache`
  for per-identity quotas. The primitives are already in the
  framework; an opinionated `Lux::RateLimit` would just lock users
  into one storage backend and one algorithm.
* **GraphQL / batch endpoint.** The API + schema story covers the
  same need with less ceremony.
* **Asset pipeline beyond CDN URLs.** Sprockets / Propshaft is a
  full-time job; we delegate to the browser and the CDN.
* **OAuth provider mode.** Big scope, narrow audience; consumer-side
  via `plugins/oauth` is enough.
* **Per-mount DI container (Hanami slices).** Plugin layout already
  scopes ownership; another container layer is more complexity than
  payoff.

## Top three if forced to pick

Original list was 2/3 shipped (routes, opt DSL). Refreshed:

1. **CSRF default-on** - still the loudest security gap; trivial to
   add, embarrassing to lack.
2. **WebSocket / SSE / streaming** - `response.stream { }` +
   `response.sse` on the existing Rack-clean response API. Real
   differentiator vs Sinatra/Roda.
3. **CORS + request ID + dev error page context** as one "production
   readiness" patch - all three are blockers for putting a lux app
   behind a real domain or debugging it in dev.
