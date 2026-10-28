# Lux framework - agent index

Ruby web framework. Rack + Sequel + PostgreSQL. Sinatra speed,
Rails-shaped routers, Hanami-style schemas, **one shared DSL across
routers, APIs, models, and schemas**.

Do not program Ruby as Java. Ruby is Ruby, dynamic and adaptive.
Use minimal code to accomplish desired task, but keep concerns separate allways.

This is the only `AGENTS.md` in the repo. Every subsystem ships a
`README.md` next to its code with the canonical example, full API, and
module-specific rules. **Before editing code in a subsystem, read that
module's `README.md`.** Links are in the tables below.

## Cross-cutting conventions

* Inside `module Lux`, `Hash` lexically resolves to `Lux::Hash`. Use
  `obj.is_hash?` (from `lib/overload/object.rb`) or fully-qualified
  `::Hash`. Same for any `Lux::<CoreClass>` / gem-name alias - notably
  `Mail` resolves to `Lux::Mail` (write `::Mail` for the gem), `Context` to
  `Lux::Context` and `Error` to `Lux::Error`.
* Use `FOO ||=` for module-level constants, not `FOO =`.
* End files with newline. No trailing spaces on blank lines.
* ASCII only - `-` not `—`, `*` not `•`. No emojis unless asked.
* Models use `ref` (string ULID) as primary key. Sequel-based ORM.
* `Lux.ctx` is the thread-local context, the only accessor. It is never
  nil; outside a request it has no request (`Lux.ctx.request` is nil), so
  request-bound code fails instead of reading a fake one.
* Versioning: `.version` is YAML (`version: X.Y.Z`) holding the commit
  count rendered dotted (`371` -> `3.7.1`, `12345` -> `123.4.5`). Only
  `hammer deploy` stamps it: tests, `vstamp count --release` (stamp, amend
  or release commit, tag `vX.Y.Z`, push), then `gem build` + `gem push`.
  No git hooks. `Lux::Version.string` reads it and `Lux::VERSION` is the
  gem form. An unstamped checkout reports `dev`. `LUX_VERSION` overrides
  the file.
  `Version` lives in `lib/lux/version.rb`.

## Routing invariants

Read [`lib/lux/router/README.md`](./lib/lux/router/README.md) before
touching the router. The three rules that catch people out:

* **`Lux.ctx.route` is the only path matcher.** It owns `match?` / `start_with?` /
  `capture` over an offset stack, and every router `map` scope (root or
  mounted) walks it. Never re-derive a match from `nav.path` indices.
* **The first match ends routing.** A dispatch that writes the body throws
  `:done`. The route walk catches `:done` once, in `Router#resolve_routes`.
  The other `catch(:done)` sites wrap a single hook (before/after callbacks, a
  rescue handler, a mounted router that re-throws when it wrote the body).
  Never add one around `map` or inside a route block - it re-enables the old
  "keep walking as no-ops" behaviour and silently re-runs work after a match.
  `render` and `redirect_to` throw `:done` too, so code after them never runs.
* **`-` and `_` are equal at compare time only** (`Route#norm`). `nav.path`
  keeps the URL's own spelling so slug lookups work; never normalise it in
  place.
* **Two views of the path.** `nav.source_path` is the frozen original,
  `nav.path` the working copy that `nav.map_path`, `nav.locale { }` and app code
  rewrite in place. After `nav.map_path` an id reads as `'ref'` in `nav.path`
  (the route shape, used for template lookup), and its value is on the element.
  Values -> `nav.ref` / `nav.refs` / `nav.pathname`, shape -> `path`, "what
  arrived" -> `source_path`. Never snapshot `nav.path` yourself.
* **A classified id is a `Lux::Ref::Base` element.** `nav.map_path` replaces the
  segment with a format instance - a frozen String reading `'ref'` whose
  `.value` is the id - so `nav.refs` is derived from `nav.path` and cannot
  drift from it. Test with `is_a?(Lux::Ref::Base)`, never `== 'ref'`; `:ref` in
  a route pattern is matched by type, so a URL segment spelled `ref` is not
  one. `nav.ref` is read-only.
* **The id format is named once, by `Lux.config.ref_format`.** Never hardcode a
  format class. `nav.map_path`, `Lux::Type::RefType` (validation *and* column
  width), `Lux::Ref.generate` (primary keys) and `load_models` all resolve
  through `Lux::Ref.resolve` / `.build`, so an app that switches to `:uuid7`
  moves all four together. New shapes subclass `Lux::Ref::Base` (or `Short` /
  `Slug`) and `Lux::Ref.register` a name. See [`lib/lux/ref/README.md`](./lib/lux/ref/README.md).

There are no per-action URL macros and no `_ref` action suffix - URLs are
declared in the router. See [`doc/migration-routing.md`](./doc/migration-routing.md)
for what was removed and why, and [`doc/migration-router.md`](./doc/migration-router.md)
for moving an app from controllers to routers. Note `Lux::Api.ref` is a
separate, live macro on a different class.

## The unified DSL

`Lux::Schema::Define` (`lib/lux/schema/define.rb`) is the shared line
parser used by `Lux::Router#opt` / `params do`, `Lux::Api.params`,
standalone `Lux::Schema`, model `schema do` blocks, and DB migrations.

```ruby
opt :name, String, max: 30                 # method-level (above def)
name String, max: 30                       # in-block shortcut
set :name, type: String, max: 30           # explicit
```

Field-name suffix `?` marks optional. Type vocabulary is any built-in
(`String`, `Integer`, `Boolean`, ...) or a named `Lux::Type` (`:email`,
`:url`, `:uuid`, `:slug`, `:locale`, `:translated`, ...). **When generating params code
anywhere, use this DSL.** Don't invent per-router validators.

## One way to do it

Generate these forms; the alternatives the code still accepts exist for
internal use and old apps.

| Task | Canonical form | Read |
|------|----------------|------|
| Route a path | `map 'users'` (== `map 'users', 'users'`) / `map 'users', UsersRouter` / `map 'users', 'users#index'` (match, then target) / `map 'admin' do ... end` / `root 'main#index'` / one-arg `map MainRouter` or `map 'users#index'` (no match) inside `Lux.router { route do ... end }` (app/routes.rb); other shapes raise | [router](./lib/lux/router/README.md) |
| Mount an API | `map 'api', ApplicationApi` | [api](./lib/lux/api/README.md) |
| Validate params | `opt :name, String, max: 30` above `def`, or `params do ... end` | [router](./lib/lux/router/README.md) |
| JSON endpoint | `define :name do proc { ... } end` in a `Lux::Api` class | [api](./lib/lux/api/README.md) |
| Fail a request | `raise Lux.error.not_found 'no such user'` (`forbidden`, `bad_request`, ...) | [error](./lib/lux/error/README.md) |
| Access check | `@model.can.read?` (policy class `ModelPolicy`) | [policy](./lib/lux/policy/README.md) |
| Render | implicit `app/views/<router>/<action>.haml`, or `render text:` / `render json:` | [router](./lib/lux/router/README.md) |
| Redirect + flash | `response.flash.info 'Saved'` then `response.redirect_to '/path'` | [response](./lib/lux/response/README.md) |
| Request context | `Lux.ctx` (`Lux.ctx.request` is nil outside a request) | [context](./lib/lux/context/README.md) |
| Cache | `Lux.cache.fetch(key, ttl: 60) { ... }` | [cache](./lib/lux/cache/README.md) |
| Background job | `LuxJob.add :name, opts` (job_runner plugin), `Lux.defer { }` for fire-and-forget | [job_runner](./plugins/job_runner/README.md) |
| Ship assets | `lux assets:deploy` (generate `app/assets/*.tmp.*` -> compile -> manifest -> upload); the app defines `lux assets:compile` and `lux assets:upload LOCAL_PATH REMOTE_PATH` in `lib/tasks` | [web_common](./plugins/web_common/README.md) |
| Call a model API from JS | `app.m.user(ref).update({...})` (`app.m.user.create({...})` for collection actions) | [web_common](./plugins/web_common/README.md#model-handles) |
| Mail | `class Mailer < Lux::Mail::Sender`, `Mailer.deliver(:welcome, user)` | [mail](./lib/lux/mail/README.md) |
| Model fields | `schema do ... end` in the model, migrated by `lux db:am` | [db](./plugins/db/README.md) |
| User text / HTML | stored as typed, escaped on output by Haml `=`; build markup with `.tag` (returns `Lux::SafeString`), print trusted stored markup with `.html_unsafe` (not a sanitizer - only `<script>`/`<style>` are disabled; never on user-supplied HTML); never `%[<b>#{x}</b>]` | [overload](./lib/overload/README.md#output-escaping) |
| Push to a browser | `Lux.channel(user).push(...)` + `Lux::Browser::Channel.session_channels { }` in an initializer; `Lux.subscribe('user:<ref>', fn)` client-side | [browser-push](./doc/browser-push.md) |

## Core modules - `lib/lux/<name>/`

| Module | What it is | Read |
|--------|------------|------|
| `Lux::Router`          | Root router + app routers (`class MainRouter < ApplicationRouter`): `route do ... end` with `map`, actions, `opt` / `params do`, rendering | [README](./lib/lux/router/README.md) |
| `Lux::Api`             | JSON API classes; same params DSL as routers               | [README](./lib/lux/api/README.md) |
| `Lux::Schema`          | The shared schema DSL parser at the heart of the framework | [README](./lib/lux/schema/README.md) |
| `Lux::Type`            | Named type vocabulary (`:email`, `:uuid`, `:slug`, ...)    | [README](./lib/lux/type/README.md) |
| `Lux::Ref`             | The app id format (`Lux.config.ref_format`): `generate` / `is?`, formats, `nav.path` id elements | [README](./lib/lux/ref/README.md) |
| `Lux::Policy`          | Framework- and ORM-agnostic access policy                  | [README](./lib/lux/policy/README.md) |
| `Lux::Context`         | Thread-local context (`Lux.ctx`); request-less outside a request | [README](./lib/lux/context/README.md) |
| `Lux::Response`        | HTTP response builder (`response` inside routers)          | [README](./lib/lux/response/README.md) |
| `Lux::Render`          | Render pages, templates, cells from anywhere               | [README](./lib/lux/render/README.md) |
| `Lux::Template`        | Template rendering via Tilt (HAML, ERB, ...)               | [README](./lib/lux/template/README.md) |
| `Lux::ViewCell`        | Reusable view components with their own templates          | [README](./lib/lux/view_cell/README.md) |
| `Lux::Mail`            | Inbound + outbound mail: `Sender` (compose/send) + `Inbox` (`on_receive` event, IMAP `mail:pull`) | [README](./lib/lux/mail/README.md) |
| `Lux::Cache`           | Uniform cache API across memory/memcached/sqlite/null      | [README](./lib/lux/cache/README.md) |
| `Lux::Db`              | Sequel multi-DB connection management                      | [README](./lib/lux/db/README.md) |
| `Lux::Browser`         | Server-side composer for `window.Lux` client + per-request state | [README](./lib/lux/browser/README.md) |
| `Lux::Browser::Channel`| Pub/sub behind `/_lux_/stream` (`Lux.channel(x).push` -> `Lux.subscribe`); backend via `channel_url` | [README](./lib/lux/browser/channel/README.md) |
| `Lux::Error`           | Thin exception class + `Lux.error.not_found` style helpers | [README](./lib/lux/error/README.md) |
| `Lux::Defer`          | `Lux.defer { }` fire-and-forget background work             | [README](./lib/lux/defer/README.md) |
| `Lux::Root`            | App root (Pathname) plus plugin `mount/` overlays (`.path`, `.file`, `.files`, `.require_all`) | [README](./lib/lux/plugin/README.md#mount-semantics-mount) |
| `Lux::Environment`     | `Lux.env` / `Lux.debug?` / `Lux.runtime` facets              | [README](./lib/lux/environment/README.md) |
| `Lux::DEPLOY_ID`       | Stable per-deploy id for cache-busting; mirrored to `ENV['DEPLOY_ID']` | [README](./README.md#luxdeploy_id) |
| `Lux::Boot::Config`          | YAML config + `.env` loader + lifecycle hooks              | [README](./lib/lux/boot/config/README.md) |
| `Lux::Plugin`          | Plugin loader (`Lux.root/plugins` then `Lux.fw_root/plugins`) | [README](./lib/lux/plugin/README.md) |
| `Lux::Reloader`        | Fast code reloader; skips installed gems via `Gem.path`    | [README](./lib/lux/reloader/README.md) |
| `Lux::Logger`          | Default + named loggers with rotation                      | [README](./lib/lux/logger/README.md) |
| `Lux::Shell`           | Secure shell/process exec + `info`/`error`/`die` helpers   | [README](./lib/lux/shell/README.md) |
| `Lux::Hash`            | Hash with indifferent string/symbol/method access          | [README](./lib/lux/hash/README.md) |
| `Lux::JsonExporter`    | Structured JSON export with named exporters per model      | [README](./lib/lux/json_exporter/README.md) |
| `Lux::Utils`           | Pure helpers (`Crypt`, `Url`, `StringBase`, `Json`, ...)   | [README](./lib/lux/utils/README.md) |

## Plugins - `plugins/<name>/`

| Plugin            | What it is | Read |
|-------------------|------------|------|
| `db`              | Sequel extensions (hooks, links, paginate, enums) + auto-migrate | [README](./plugins/db/README.md) |
| `authcog`         | Central-auth sign-in: `AuthcogRouter` + `UserSession`               | [README](./plugins/authcog/README.md) |
| `web_common`      | Shared web layer: html builders, asset pipeline, JSON exception log (dboss), `/dev` pages, `ModelApi`, browser lib (`$`, `Api`, `Toast`, `<api-form>`); list `authcog` next to it | [README](./plugins/web_common/README.md) |
| `locale`          | Small, namespaced translation lookup + `/<xx>` URL prefixes (`localized`, `Lux.ctx.lpath`) | [README](./plugins/locale/README.md) |
| `favicon`         | `public/favicon.svg` -> generated `.ico` + touch icon, `<head>` links from `Lux.ctx.render_html` / `header.render` (`el.icon false` opts out) | [README](./plugins/favicon/README.md) |
| `job_runner`      | Postgres-backed job queue (LISTEN/NOTIFY + advisory locks) + standalone web dashboard | [README](./plugins/job_runner/README.md) |
| `pdf`             | Paged.js A4 pages under `/pdf/` + headless-Chrome PDF download     | [README](./plugins/pdf/README.md) |
| `vibe`            | Docker harness: opencode agent + preview page for editing an app   | [README](./plugins/vibe/README.md) |

Plugin specs live in `plugins/<name>/spec/` and run with `bundle exec hammer test`.

## Repo layout

```
lib/lux/<module>/         # core modules; each ships a README.md
lib/lux/test/             # Lux::Test - test scaffolding (Minitest + Factory + helpers)
lib/overload/             # Ruby core class extensions (don't touch lightly)
plugins/<name>/           # optional plugins, canonical layout
spec/<area>_tests/        # Minitest::Spec - per-area suites
bin/cli/<name>_hammer.rb  # CLI subcommands
```

## Testing

* Framework: **Minitest::Spec**. RSpec is gone.
* Entry point: every spec starts with `require 'test_helper'`. The helper loads lux, `Lux::Test`, and `spec/factories.rb`.
* Base class: `Lux::Test::Case` (transparently mixed into every `describe` block).
* Factories: vendored clean-mock at `lib/lux/test/factory/`, exposed as `factory` in every spec.
* Helpers available everywhere: `factory`, `capture_log`/`capture_stdout`/`capture_stderr`, `with_transaction`, plus `assert_status` / `assert_redirect` / `assert_body_includes` / `assert_json_includes`.
* HTTP requests: use `Lux.render.get/post/...` - returns a `Lux::Router::Page` with `.status`, `.body`, `.json`, `.headers`, `.redirect_to`, `.ok?`, `.session`. `Lux.render.client` carries the session between calls.
* Rulebook for writing tests: **[`lib/lux/test/AGENTS.md`](./lib/lux/test/AGENTS.md)**. AI agents converting or writing specs must read it first - it lists the only allowed assertions and the banned RSpec syntax.
* Run: `bundle exec hammer test` (folder-isolated). Single folder: `hammer test --folder lux_tests`. Per-spec processes: `hammer test --isolated`. Tasks are defined in `./Hammerfile` (powered by the `lux-hammer` gem - replaces Rake).

## Boot model

Two-phase. `require 'lux-fw'` runs framework load (gems, overloads,
`Lux::*` subsystems, Sequel + Haml).
Framework load does no DB connect, no `.env`, no plugin loaders; it does create `./log` and `./tmp` and resolves `Lux::DEPLOY_ID`.
`Lux.boot!` then runs app boot: `.env` load, `LUX_ENV` check, `init_env`, `Bundler.require`, ENV-dependent defaults (`log_level`, `channel_url`), config typo warnings, the optional boot block, app autoloads (`Lux::Root.autoload!`), plugin loaders, channel listener (web only).
The first `Lux.config` read loads `config.yaml` and fills the remaining framework defaults (`Lux::Boot.apply_defaults`), so `Lux.logger` / `Lux.log` / `Lux.defer` work before boot.
Idempotent and thread-safe. There is no `const_missing` hook.

Canonical host `config/env.rb`:

```ruby
require 'bundler/setup'
require 'lux-fw'
Lux.boot!
```

See `lib/lux/router/README.md` and `lib/lux/boot/config/README.md` for
entry-point details.

## Adding code

* Edit existing files in preference to creating new ones.
* Comment only the non-obvious why - never the what.
* Reuse existing primitives: check `Lux.schema(:name)` in `SCHEMA_STORE`,
  `Lux::Type::*Type` under `lib/lux/type/types/`, and `Lux::Policy`
  descendants. Don't invent new primitives that duplicate framework ones.
* Specs go under `spec/<area>_tests/` (e.g. `spec/lux_tests/`,
  `spec/lib_tests/`, `spec/api_tests/`). Run with `bundle exec hammer test`.
  See [`lib/lux/test/AGENTS.md`](./lib/lux/test/AGENTS.md) for test-writing
  rules - only the documented Minitest assertions and `Lux::Test` helpers
  are allowed.
* Never commit or push without explicit user instruction.
