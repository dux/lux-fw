# Lux framework - agent index

Ruby web framework. Rack + Sequel + PostgreSQL. Sinatra speed,
Rails-shaped controllers, Hanami-style schemas, **one shared DSL across
controllers, APIs, models, and schemas**.

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
  `Mail` resolves to `Lux::Mail`, so write `::Mail` for the gem.
* Use `FOO ||=` for module-level constants, not `FOO =`.
* End files with newline. No trailing spaces on blank lines.
* ASCII only - `-` not `—`, `*` not `•`. No emojis unless asked.
* Models use `ref` (string ULID) as primary key. Sequel-based ORM.
* `Lux.current` (alias `lux`) is the thread-local request context.

## The unified DSL

`Lux::Schema::Define` (`lib/lux/schema/define.rb`) is the shared line
parser used by `Lux::Controller#opt` / `params do`, `Lux::Api.params`,
standalone `Lux::Schema`, model `schema do` blocks, and DB migrations.

```ruby
opt :name, String, max: 30                 # method-level (above def)
name String, max: 30                       # in-block shortcut
set :name, type: String, max: 30           # explicit
```

Field-name suffix `?` marks optional. Type vocabulary is any built-in
(`String`, `Integer`, `Boolean`, ...) or a named `Lux::Type` (`:email`,
`:url`, `:uuid`, `:slug`, `:locale`, `:translated`, ...). **When generating params code
anywhere, use this DSL.** Don't invent per-controller validators.

## Core modules - `lib/lux/<name>/`

| Module | What it is | Read |
|--------|------------|------|
| `Lux::Application`     | Router + request lifecycle; routing DSL at top level or in an optional `routes do` | [README](./lib/lux/application/README.md) |
| `Lux::Controller`      | Rails-shaped HTTP controllers with `opt` / `params do`     | [README](./lib/lux/controller/README.md) |
| `Lux::Api`             | JSON API classes; same params DSL as controllers           | [README](./lib/lux/api/README.md) |
| `Lux::Schema`          | The shared schema DSL parser at the heart of the framework | [README](./lib/lux/schema/README.md) |
| `Lux::Type`            | Named type vocabulary (`:email`, `:uuid`, `:slug`, ...)    | [README](./lib/lux/type/README.md) |
| `Lux::Policy`          | Framework- and ORM-agnostic access policy                  | [README](./lib/lux/policy/README.md) |
| `Lux::Current`         | Thread-local per-request context (`Lux.current` / `lux`)   | [README](./lib/lux/current/README.md) |
| `Lux::Response`        | HTTP response builder (`response` inside controllers)      | [README](./lib/lux/response/README.md) |
| `Lux::Render`          | Render pages, controllers, templates, cells from anywhere  | [README](./lib/lux/render/README.md) |
| `Lux::Template`        | Template rendering via Tilt (HAML, ERB, ...)               | [README](./lib/lux/template/README.md) |
| `Lux::ViewCell`        | Reusable view components with their own templates          | [README](./lib/lux/view_cell/README.md) |
| `Lux::Mail`            | Inbound + outbound mail: `Sender` (compose/send) + `Inbox` (`on_receive` event, IMAP `mail:pull`) | [README](./lib/lux/mail/README.md) |
| `Lux::Cache`           | Uniform cache API across memory/memcached/sqlite/null      | [README](./lib/lux/cache/README.md) |
| `Lux::Db`              | Sequel multi-DB connection management                      | [README](./lib/lux/db/README.md) |
| `Lux::Browser`         | Server-side composer for `window.Lux` client + per-request state | [README](./lib/lux/browser/README.md) |
| `Lux::Browser::Channel`| In-process pub/sub backing `response.sse` streams          | [README](./lib/lux/browser/channel/README.md) |
| `Lux::Error`           | Thin exception class + `Lux.error.not_found` style helpers | [README](./lib/lux/error/README.md) |
| `Lux::Environment`     | `Lux.env` / `Lux.mode` / `Lux.runtime` facets              | [README](./lib/lux/environment/README.md) |
| `Lux::DEPLOY_ID`       | Stable per-deploy id for cache-busting; mirrored to `ENV['DEPLOY_ID']` | [README](./README.md#luxdeploy_id) |
| `Lux::Boot::Config`          | YAML config + `.env` loader + lifecycle hooks              | [README](./lib/lux/boot/config/README.md) |
| `Lux::Plugin`          | Plugin loader (`Lux.root/plugins` then `Lux.fw_root/plugins`) | [README](./lib/lux/plugin/README.md) |
| `Lux::Reloader`        | Fast code reloader; skips installed gems via `Gem.path`    | [README](./lib/lux/reloader/README.md) |
| `Lux::Logger`          | Default + named loggers with rotation                      | [README](./lib/lux/logger/README.md) |
| `Lux::Shell`           | Secure shell/process exec + `info`/`error`/`die` helpers   | [README](./lib/lux/shell/README.md) |
| `Lux::Hash`            | Hash with indifferent string/symbol/method access          | [README](./lib/lux/hash/README.md) |
| `Lux::JsonExporter`    | Structured JSON export with named exporters per model      | [README](./lib/lux/json_exporter/README.md) |
| `Lux::Utils`           | Pure helpers (`Crypt`, `StringBase`, `Json`, ...)          | [README](./lib/lux/utils/README.md) |

## Plugins - `plugins/<name>/`

| Plugin            | What it is | Read |
|-------------------|------------|------|
| `db`              | Boots `Lux::Db` + Sequel extensions (hooks, links, paginate, enums) | [README](./plugins/db/README.md) |
| `web_common`      | Shared web layer: html builders, assets, authcog controller, PG exception logger + `/admin` | [README](./plugins/web_common/README.md) |
| `locale`          | Small, namespaced translation lookup with dotted keys              | [README](./plugins/locale/README.md) |
| `oauth`           | Oauth interface (facebook, github, google, linkedin, slack, ...)   | [README](./plugins/oauth/README.md) |
| `job_runner`      | Postgres-backed job queue (LISTEN/NOTIFY + advisory locks)         | [README](./plugins/job_runner/README.md) |
| `lux_logger`      | Database-backed structured logger                                  | [README](./plugins/lux_logger/README.md) |

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
* HTTP requests: use `Lux.render.get/post/...` - returns a `Lux::Response` with `.status`, `.body`, `.json`, `.headers`, `.redirect_to`, `.ok?`.
* Rulebook for writing tests: **[`lib/lux/test/AGENTS.md`](./lib/lux/test/AGENTS.md)**. AI agents converting or writing specs must read it first - it lists the only allowed assertions and the banned RSpec syntax.
* Run: `bundle exec hammer test` (folder-isolated). Single folder: `hammer test --folder lux_tests`. Per-spec processes: `hammer test --isolated`. Tasks are defined in `./Hammerfile` (powered by the `lux-hammer` gem - replaces Rake).

## Boot model

Two-phase. `require 'lux-fw'` runs framework load (gems, overloads,
`Lux::*` subsystems, Sequel + Haml) - no side effects on the host: no
DB connect, no `.env`, no plugin loaders. `Lux.boot!` then runs app
boot: `init_env`, `dotenv`, `bundler_require!`, `config`,
`Config.set_defaults`, then plugin loaders. Idempotent.

Canonical host `config/env.rb`:

```ruby
require 'bundler/setup'
require 'lux-fw'
Lux.boot!
```

See `lib/lux/application/README.md` and `lib/lux/boot/config/README.md` for
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
