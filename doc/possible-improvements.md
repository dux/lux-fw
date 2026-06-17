# Possible improvements

Cross-referenced against the top recurring complaints in Rails, Sinatra, Hanami, and Roda over the last ~3-5 years
(GitHub issues, blog posts, HN/Reddit threads, conference talks). Each item notes which framework faces the same pain
or, conversely, which framework already solved it in a way worth copying.

## Great - we have

Differentiators. The places lux is ahead of Sinatra/Roda/Hanami, not just at parity.

* **Tree routing** with `map` / `call` / `match` and `route.with_scope` (Roda-style cursor, no nav mutation).
* **Plugin system** with canonical layout (`loader.rb`, `load/`, `hammer/`, `mount/`) - better discoverability than
  Roda's flat plugin list.
* **Unified schema / type system** (`lib/lux/schema`, `lib/lux/type`) - covers controller params, model columns, API
  contracts, and enum DSL from one source. Hanami needs dry-validation + dry-types + dry-schema.
* **API introspect + OpenAPI 3 + Postman + AGENTS.md emit** (`lib/lux/api/doc/*`, served via `/<mount>/sys/*`). The
  unified `Lux::Schema` DSL pays off: API contract is generated, not maintained. No other Ruby framework ships the
  LLM-targeted AGENTS endpoint.
* **`bin/lux routes`** shadow-replays route callbacks against a recording instance; `-v` adds source locations
  (`lib/lux/application/lib/routes_dumper.rb`).
* **SSE streaming + cross-worker pub/sub.** `response.sse(:channel, ...)` + `Lux::Browser::Channel` with optional PG
  LISTEN/NOTIFY broker for fan-out across Puma workers. ~150 LOC end-to-end (`lib/lux/response/lib/sse.rb`,
  `lib/lux/browser/channel/`). Sinatra/Roda need plugins, Rails carries the weight of ActionCable.
* **Per-request browser state composer.** `lux.browser.window[:app] = {...}` emits a deduped `<script>` tag; pairs with
  the `Lux::Browser.client_js` bundler for the framework client lib (csrf, fetch, sse). Nothing else in Ruby has this
  shape.
* **Custom reloader that skips `Gem.path`** - addresses the Rails "reload-degradation" complaint head-on
  (`lib/lux/reloader/`).
* **Exception logger with mountable viewer** (`plugins/web_common`). Hanami / Sinatra miss this entirely.
* **CSRF + CORS first-class on the response object.** `response.cors :all`, auto-injected CSRF token in `HtmlForm`,
  preflight handled at the application level (`lib/lux/response/lib/cors.rb`, `lib/lux/current/lib/csrf.rb`).
* **Job runner with PG LISTEN/NOTIFY trigger + advisory lock + exponential backoff.** Single-DB, no Redis required, no
  Sidekiq tax (`plugins/job_runner/lib/lux_job.rb`). Admin dashboard mounts via `lux mount job_runner`.
* **`rescue_from` at app and controller level** (`Lux::Application.rescue_from`, `Lux::Controller.rescue_from`) with a
  documented resolution order (app > controller :error > framework default).
* **Pagination** end-to-end: `Lux::Utils::PaginatedArray`, Sequel `paginate` ext (`plugins/db/ext/paginate.rb`), and
  `HtmlHelper.paginate` view helper (`plugins/web_common/load/html/html_paginate.rb`).
* **Enum DSL** in schema blocks (`enum :status do |f| ... end`) - emits Sequel column + helpers + validation +
  `for_select`; backed by the db plugin (`plugins/db/lib/schema_define.rb`).
* **Shell API.** `Lux::Shell.exec` strips output and raises on failure (or yields `(err, out)` to a block);
  `Lux::Shell.capture` is merged stdout+stderr, never raises; `Lux.shell.die` auto-appends caller for fatal user errors.

## OK - we have

Present and working, but shallow compared to what the equivalent ecosystem ships. Worth deepening, not rewriting.

* **Response API.** `halt`, `etag`, `early_hints`, `send_file`, `auth`, `sse`, `stream`, `cors`. Solid surface; lacks a
  `redirect_back` / `referer`-aware helper and a generic `response.error(msg, status:)` that other frameworks have.
* **Policy proxy + `Lux.current` thread-local + JWT sessions.** Works, but `Lux.current` is thread-local; fiber-safe
  storage would future-proof against Falcon-style runtimes.
* **i18n** via `plugins/locale` - namespaced lookups, dynamic namespaces, before/after hooks, `t` helper auto-exposed
  in templates. Good for app code; missing model-attribute and validation-message conventions Rails has.
* **JSON content negotiation by default** (`params_dsl.rb:114`, `controller.rb:211`) - request body sniffing flips the
  response content type. Works; the equivalent on outbound (force JSON for `Accept: application/json`) is partial.
* **CLI generators** (`plugins/web_common/hammer/generate_hammer.rb`) - reads bundled `generate/*` templates (or app override `./config/templates/*`) and writes files interactively.
  Enough to bootstrap a file; not a real scaffold (no `lux generate resource User` that emits controller + spec + route
  + schema + admin view in one shot).
* **Health probe** at `/<mount>/sys/health`. Returns `{ ok: true, schema_version: ... }`; lacks dependency checks
  (DB ping, redis if present, job runner heartbeat).
* **Encrypted helpers** via `Lux::Utils::Crypt` (`Lux.crypt`). Present as primitives; not surfaced as a credentials
  store (`config/credentials.enc.yaml` decrypted at boot) nor as a Sequel column plugin.
* **`HtmlForm` + schema integration.** Builds inputs from a schema-backed object; CSRF auto-injected. Auto-binding
  from a form input to its schema error (`Lux::Current.errors`) is half-wired - convention is there, no
  `form_for(schema)` shorthand that closes the loop the way Hanami does with dry-validation.
* **Multi-DB ergonomics** via `Lux.db(:name)`. Arguably better than Rails; light on docs.
* **Admin UI.** `plugins/web_common` exists and renders CRUD over Sequel models; no `lux generate admin_resource User`
  that emits a tailored page.
* **Mailer** (`lib/lux/mailer`) - templates + delivery. No preview route, no `deliver_later` wiring to `LuxJob` (every
  host app rolls its own).

## Critical - missing or thin

Things every framework gets burned on. lux still missing or skin-deep.

* **Dev error page context.** `Lux::Error.render` shows status, message, and a backtrace. No request body, no params,
  no source snippet around the failing line, no `Lux.current` dump. Roda's #1 complaint is exactly this. The data is
  on `Lux.current`; rendering it in dev is HtmlTag plumbing.
* **Request ID / correlation ID.** No `X-Request-Id` propagation, no `Lux.current.request_id` field (the existing
  `lux.uid` is a per-call counter, not a request-scoped trace id). Without it, structured logs across web + jobs +
  outbound HTTP can't be correlated. One-liner middleware, but has to exist before observability is useful.
* **`Mailer.deliver_later`.** `plugins/job_runner` and `lib/lux/mailer` exist independently. Wire them so
  `UserMailer.welcome(u).deliver_later` enqueues via `LuxJob`. Today every app rolls its own and gets retries wrong.
* **Hot-reload edge cases.** The Rails complaint #1 is reloader breakage with custom containers / subclasses. AGENTS
  guide documents `load`-based reopen + "methods removed from source linger" - verify with a spec that `Lux::*`
  constant redefinition, plugin reload, and controller subclassing all survive. Today this is folklore, not a test.

## Mid - missing or thin

Recurring but lower frequency. Each is small and self-contained.

* **Mailer previews.** Rails has it, everyone else is jealous. Pair cleanly with the existing `/sys` namespace:
  `/sys/mailer_previews` listing classes under `app/mailers/previews/`, click through to render in dev. ~80 LOC.
* **Scaffold generator.** `lux generate resource User name:string email:string` emits controller + spec + route +
  schema + admin view in one shot, opinionated about the unified DSL. Today's generator only reads templates.
* **File upload primitive.** No abstraction over multipart - host apps reinvent S3 PUT every time. A `Lux::Upload` with
  signed-URL generation, local-disk dev fallback, and a `:file` schema type would close the gap without ActiveStorage
  scope creep.
* **Webhook ingest primitive.** Signature verification (Stripe/GitHub/Slack style), idempotency keys, replay
  protection. No Ruby framework ships this; being first is a real differentiator.
* **Encrypted credentials store.** `Lux::Utils::Crypt` is here; surface it as a credentials store
  (`config/credentials.enc.yaml` decrypted at boot, edited via `bin/lux secrets edit`) and a Sequel column plugin so
  encrypted-at-rest is a one-liner.
* **HTTP outbound client wrapper.** Every app pulls Faraday/HTTP.rb separately. A thin `Lux.http` with timeouts +
  retries + structured logging keyed by request id matches the "batteries where it matters" stance.
* **Structured (JSON) request logger mode.** `plugins/lux_logger` is a DB-backed event audit log, not the request log.
  Verify (or add) JSON-lines output keyed by request id for prod log shipping.
* **Test helpers shipping with framework.** Specs live under `spec/lux_tests/` but there's no `Lux::Spec::Request` for
  host apps to consume - they reinvent `Rack::MockRequest` wrappers. Extracting one would help adoption more than
  another README.
* **Dev console with request replay.** `bin/lux console` exists but no "replay last request" affordance. Hanami and
  Rails both have it; the data is already in `Lux.current` and the exception log.
* **Async / Falcon / fiber-friendly.** Rails finally got it. lux uses `Lux.defer` threads; making `Lux.current`
  fiber-local instead of thread-local would future-proof without forcing a rewrite.
* **Admin UI generator.** `plugins/web_common` exists; an `lux generate admin_resource User` that emits a CRUD page
  multiplies its value. Pairs naturally with the scaffold generator.
* **Form -> schema error auto-binding.** `HtmlForm` + schema + `Lux::Current.errors` are all there; the last 20% is a
  `form_for(schema)` helper that reads errors and renders them next to the offending input. The unified DSL makes this
  almost free.
* **Job runner dead-letter view.** Retry + backoff are in; verify dead-letter handling and surface a Sidekiq-Web
  equivalent through `admin_web` (the `lux mount job_runner` views are the seed).

## Intentionally out of scope

Things people will ask for that the framework deliberately does not own. Pitched, considered, declined - kept here so
they don't get re-pitched.

* **Rate limiting.** Belongs at the edge (nginx, Cloudflare, ALB) for IP/coarse limits, or as a per-route before-filter
  using `Lux.cache` for per-identity quotas. The primitives are already in the framework; an opinionated
  `Lux::RateLimit` would just lock users into one storage backend and one algorithm.
* **GraphQL / batch endpoint.** The API + schema story covers the same need with less ceremony.
* **Asset pipeline beyond CDN URLs.** Sprockets / Propshaft is a full-time job; we delegate to the browser and the
  CDN. `plugins/web_common/load/assets/cdn_asset.rb` is enough for the lux philosophy.
* **OAuth provider mode.** Big scope, narrow audience; consumer-side via `plugins/oauth` is enough.
* **Per-mount DI container (Hanami slices).** Plugin layout already scopes ownership; another container layer is more
  complexity than payoff.
* **Zeitwerk-style lazy autoloader.** Considered as a replacement for the boot-time `Dir.require_all` sweep over
  `lib/lux/`. Doable in ~2-3 days but doesn't earn its keep: cold-boot is already fast, the framework has a custom
  reloader plus a `const_missing` autoloader for `./app/**`, and `lux_adapter.rb` files (which reopen the `Lux` module
  to add `Lux.shell`/`Lux.cache`/...) define no new constants and can't be lazy-loaded anyway. The savings would be
  marginal and the risk to the reloader interaction is real.
* **Time / clock injection (`Lux.now` / `Lux.clock`).** Saving one Timecop dep isn't worth another framework
  primitive. Host apps that want injectable time can wrap `Time.now` themselves in a few lines.
* **Static types (Sorbet / RBS).** Ruby-wide problem. The schema/type system already covers runtime; shipping RBS for
  the public surface would be polish, not a structural win.

## Top three if forced to pick

1. **Dev error page context** - `Lux::Error.render` is currently status + message + backtrace. Add request body,
   params, source snippet around the failing line, and a `Lux.current` dump. You'd feel this every debug session.
2. **Request ID propagation** - foundation for structured logging and any future observability story; ~20 LOC of
   middleware + a `Lux.current.request_id` accessor unlocks the JSON logger, the HTTP client wrapper, and the job
   runner correlation in one move.
3. **`Mailer.deliver_later` wiring** - the two halves are shipped (`LuxJob`, `Lux::Mailer`); gluing them removes the
   single most-reinvented snippet in every host app.
