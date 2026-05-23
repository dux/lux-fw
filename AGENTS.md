# Lux framework - agent index

Ruby web framework. Rack + Sequel + PostgreSQL. Sinatra speed,
Rails-shaped controllers, Hanami-style schemas, **one shared DSL across
controllers, APIs, models, and schemas**.

This is the only `AGENTS.md` in the repo. Every subsystem ships a
`README.md` next to its code with the canonical example, full API, and
module-specific rules. **Before editing code in a subsystem, read that
module's `README.md`.** Links are in the tables below.

## Cross-cutting conventions

* Inside `module Lux`, `Hash` lexically resolves to `Lux::Hash`. Use
  `obj.is_hash?` (from `lib/overload/object.rb`) or fully-qualified
  `::Hash`. Same for any `Lux::<CoreClass>` alias.
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
`:url`, `:uuid`, `:slug`, `:locale`, ...). **When generating params code
anywhere, use this DSL.** Don't invent per-controller validators.

## Core modules - `lib/lux/<name>/`

| Module | What it is | Read |
|--------|------------|------|
| `Lux::Application`     | Router + request lifecycle; routing DSL inside `routes do` | [README](./lib/lux/application/README.md) |
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
| `Lux::Mailer`          | Mail composition + template rendering (over `mail`)        | [README](./lib/lux/mailer/README.md) |
| `Lux::Cache`           | Uniform cache API across memory/memcached/sqlite/null      | [README](./lib/lux/cache/README.md) |
| `Lux::Db`              | Sequel multi-DB connection management                      | [README](./lib/lux/db/README.md) |
| `Lux::Browser`         | Server-side composer for `window.Lux` client + per-request state | [README](./lib/lux/browser/README.md) |
| `Lux::Browser::Channel`| In-process pub/sub backing `response.sse` streams          | [README](./lib/lux/browser/channel/README.md) |
| `Lux::Error`           | Thin exception class + `Lux.error.not_found` style helpers | [README](./lib/lux/error/README.md) |
| `Lux::Environment`     | `Lux.env` / `Lux.mode` / `Lux.runtime` facets              | [README](./lib/lux/environment/README.md) |
| `Lux::Config`          | YAML config + `.env` loader + lifecycle hooks              | [README](./lib/lux/config/README.md) |
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
| `html`            | HTML builders (form, input, table, menu, paginate, filter) + `PageMeta` | [README](./plugins/html/README.md) |
| `header`          | Per-request `<head>` builder, exposed as `lux.header`              | [README](./plugins/header/README.md) |
| `assets`          | Asset generation and template helpers                              | [README](./plugins/assets/README.md) |
| `favicon`         | Serves a single SVG favicon                                        | [README](./plugins/favicon/README.md) |
| `locale`          | Small, namespaced translation lookup with dotted keys              | [README](./plugins/locale/README.md) |
| `oauth`           | Oauth interface (facebook, github, google, linkedin, slack, ...)   | [README](./plugins/oauth/README.md) |
| `authcog`         | Central-auth landing controller (hash-callback exchange)           | [README](./plugins/authcog/README.md) |
| `auto_controller` | Convention-based routing + template auto-finding                   | [README](./plugins/auto_controller/README.md) |
| `admin_web`       | Skeleton admin section mounted at `/admin`                         | [README](./plugins/admin_web/README.md) |
| `job_runner`      | Postgres-backed job queue (LISTEN/NOTIFY + advisory locks)         | [README](./plugins/job_runner/README.md) |
| `exception_logger`| Postgres-backed exception logger, grouped by fingerprint           | [README](./plugins/exception_logger/README.md) |
| `lux_logger`      | Database-backed structured logger                                  | [README](./plugins/lux_logger/README.md) |

## Repo layout

```
lib/lux/<module>/         # core modules; each ships a README.md
lib/overload/             # Ruby core class extensions (don't touch lightly)
plugins/<name>/           # optional plugins, canonical layout
spec/lux_tests/           # RSpec for framework features
spec/lib_tests/           # RSpec for pure-ruby utilities
bin/cli/<name>_hammer.rb  # CLI subcommands
```

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

See `lib/lux/application/README.md` and `lib/lux/config/README.md` for
entry-point details.

## Adding code

* Edit existing files in preference to creating new ones.
* Comment only the non-obvious why - never the what.
* Reuse existing primitives: check `Lux.schema(:name)` in `SCHEMA_STORE`,
  `Lux::Type::*Type` under `lib/lux/type/types/`, and `Lux::Policy`
  descendants. Don't invent new primitives that duplicate framework ones.
* Specs go under `spec/lux_tests/` (framework) or `spec/lib_tests/`
  (pure ruby). Run with `bundle exec rspec`.
* Never commit or push without explicit user instruction.
