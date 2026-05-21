<img alt="Lux logo" width="100" height="100" src="https://i.imgur.com/Zy7DLXU.png" align="right" />

# Lux

**A Ruby web framework that unifies the primitives an enterprise backend actually
needs - so you (and your LLM) learn one DSL and use it everywhere.**

Sinatra speed, Rails-shaped controllers, Hanami-style schemas, one mental
model. Rack-based, Sequel ORM, PostgreSQL.

```bash
gem install lux-fw
lux new my-app && cd my-app && bundle exec lux s
```

## Why Lux

Enterprise backends need the same set of things: schemas, type coercion,
access policies, params validation, JSON APIs, multi-DB, background jobs,
mailers, sessions, error handling. In most frameworks these are bolted on
from different libraries with **different DSLs, different option names,
different type vocabularies**. Every new subsystem is a new dialect.

Lux ships these as first-class modules that **share the same primitives**:

* **One schema DSL** (`Lux::Schema::Define`) drives params validation in
  controllers (`opt :name, String, max: 30`), API endpoints
  (`params do ... end`), model field definitions, and DB migrations.
* **One type system** (`Lux::Type`) - `:email`, `:uuid`, `:slug`, `:locale`,
  ... - is the vocabulary everywhere a type is named.
* **One access policy** (`Lux::Policy`) used identically by controllers,
  APIs, and models (`@blog.can.read?`).
* **One request context** (`Lux.current`) used by everything that needs to
  know about the in-flight request.

The win is twofold:

1. **For humans:** learn `opt :email, type: :email, req: false` once -
   it works the same in a controller, an API, a schema block, a form helper.
2. **For LLMs:** one DSL pattern means generated code is consistent across
   the codebase, which means fewer hallucinations and better completions.
   The framework also self-documents via [`/sys/AGENTS.md`](./lib/lux/api/sys_api.rb)
   so any deployed app exposes its full API surface to agents.

## A taste of the unification

The same five lines parse identically whether they appear in a controller,
an API endpoint, a model schema, or a standalone `Lux.schema` block:

```ruby
opt :name,  String, max: 30           # or:  name  String, max: 30   (inside a block)
opt :email, type: :email              # or:  email type: :email
opt :age,   Integer, req: false       # or:  age   Integer, req: false
```

In a controller:

```ruby
class UsersController < Lux::Controller
  opt :name,  String, max: 30
  opt :email, type: :email
  def create
    # current.params is already validated, coerced, undeclared keys dropped
  end
end
```

In an API:

```ruby
class UsersApi < ApplicationApi
  desc 'Create a user'
  params do
    name  String, max: 30
    email type: :email
  end
  def create
    # @api.params is already validated, coerced
  end
end
```

In a model:

```ruby
class User < ApplicationModel
  schema do
    name  String, max: 30
    email type: :email, index: true
  end
end
```

Same line parser. Same type vocabulary. Same option keys.

## Modules

Each module has its own `README.md` (human-focused, with examples) and
`AGENTS.md` (LLM-focused, one full example).

### Request lifecycle

| Module | What | Docs |
|--------|------|------|
| `Lux::Application` | Router and request lifecycle | [README](./lib/lux/application/README.md) · [AGENTS](./lib/lux/application/AGENTS.md) |
| `Lux::Controller`  | HTTP controllers + `opt`/`params` DSL | [README](./lib/lux/controller/README.md) · [AGENTS](./lib/lux/controller/AGENTS.md) |
| `Lux::Current`     | Thread-local request context | [README](./lib/lux/current/README.md) · [AGENTS](./lib/lux/current/AGENTS.md) |
| `Lux::Response`    | HTTP response builder | [README](./lib/lux/response/README.md) · [AGENTS](./lib/lux/response/AGENTS.md) |
| `Lux::Render`      | Server-side rendering (page / template / cell) | [README](./lib/lux/render/README.md) · [AGENTS](./lib/lux/render/AGENTS.md) |

### Unified DSL stack

| Module | What | Docs |
|--------|------|------|
| `Lux::Api`     | JSON-RPC-ish API classes sharing the controller DSL | [README](./lib/lux/api/README.md) · [AGENTS](./lib/lux/api/AGENTS.md) |
| `Lux::Schema`  | Schema definition DSL (the `opt`/`params` parser core) | [README](./lib/lux/schema/README.md) · [AGENTS](./lib/lux/schema/AGENTS.md) |
| `Lux::Type`    | Named types (email, uuid, slug, locale, ...) used everywhere | [README](./lib/lux/type/README.md) · [AGENTS](./lib/lux/type/AGENTS.md) |
| `Lux::Policy`  | Access policies for controllers / APIs / models | [README](./lib/lux/policy/README.md) · [AGENTS](./lib/lux/policy/AGENTS.md) |

### Storage

| Module | What | Docs |
|--------|------|------|
| `Lux::Db`         | Sequel multi-DB connection management | [README](./lib/lux/db/README.md) · [AGENTS](./lib/lux/db/AGENTS.md) |
| `Lux::Cache`      | Memory / Memcached cache with the same fetch API | [README](./lib/lux/cache/README.md) · [AGENTS](./lib/lux/cache/AGENTS.md) |
| `Lux::Mailer`     | Mail composition + delivery with template render | [README](./lib/lux/mailer/README.md) · [AGENTS](./lib/lux/mailer/AGENTS.md) |
| `Lux::Template`   | Tilt-based template rendering + helpers | [README](./lib/lux/template/README.md) · [AGENTS](./lib/lux/template/AGENTS.md) |
| `Lux::ViewCell`   | Reusable view components with their own scope | [README](./lib/lux/view_cell/README.md) · [AGENTS](./lib/lux/view_cell/AGENTS.md) |

### Foundation

| Module | What | Docs |
|--------|------|------|
| `Lux::Config`      | YAML config + `.env` loader + hooks | [README](./lib/lux/config/README.md) · [AGENTS](./lib/lux/config/AGENTS.md) |
| `Lux::Environment` | `Lux.env` / `Lux.mode` / `Lux.runtime` | [README](./lib/lux/environment/README.md) · [AGENTS](./lib/lux/environment/AGENTS.md) |
| `Lux::Error`       | HTTP error helpers + rendering | [README](./lib/lux/error/README.md) · [AGENTS](./lib/lux/error/AGENTS.md) |
| `Lux::Logger`      | Named loggers with configurable output | [README](./lib/lux/logger/README.md) · [AGENTS](./lib/lux/logger/AGENTS.md) |
| `Lux::Plugin`      | Plugin loader with canonical folder layout | [README](./lib/lux/plugin/README.md) · [AGENTS](./lib/lux/plugin/AGENTS.md) |
| `Lux::Reloader`    | Custom code reloader (skips Gem.path) | [README](./lib/lux/reloader/README.md) · [AGENTS](./lib/lux/reloader/AGENTS.md) |
| `Lux::Hash`        | Hash with indifferent access | [README](./lib/lux/hash/README.md) · [AGENTS](./lib/lux/hash/AGENTS.md) |
| `Lux::JsonExporter`| Structured JSON export from any object | [README](./lib/lux/json_exporter/README.md) · [AGENTS](./lib/lux/json_exporter/AGENTS.md) |

### Plugins (`plugins/`)

| Plugin | What | Docs |
|--------|------|------|
| `db`               | Sequel model extensions, auto-migrate, `link` associations | [README](./plugins/db/README.md) · [AGENTS](./plugins/db/AGENTS.md) |
| `html`             | HTML builders: form, input, table, menu, paginate, filter | [README](./plugins/html/README.md) |
| `assets`           | CDN asset pipeline | [README](./plugins/assets/README.md) |
| `job_runner`       | Background job queue (LuxJob) | [README](./plugins/job_runner/README.md) |
| `lux_logger`       | Structured database logger | [README](./plugins/lux_logger/README.md) |
| `exception_logger` | PG-backed exception logger + mountable viewer | [README](./plugins/exception_logger/README.md) |
| `oauth`            | OAuth integration | [README](./plugins/oauth/README.md) |
| `auto_controller`  | Convention-based controller routing | [README](./plugins/auto_controller/README.md) |
| `authcog`          | Central-auth landing controller | [README](./plugins/authcog/README.md) |
| `favicon`          | Favicon serving | [README](./plugins/favicon/README.md) |
| `header`           | Common HTTP header helpers | [README](./plugins/header/README.md) |

## CLI

```bash
lux server         # Start web server (alias: s, ss)
lux console        # Start Pry console (alias: c)
lux render /path   # Render any path locally (session, bearer, headers)
lux routes         # Print mounted route tree
lux generate       # Generate models, cells, controllers
lux test           # Recreate test DB + run full test suite (alias: t)
lux secrets        # Display / edit ENV and secrets
lux stats          # Project stats
lux memory         # Profile memory usage
lux new APP        # Create new Lux application
lux sysd           # Systemd service management
```

See [`bin/README.md`](./bin/README.md) for full CLI docs.

## Convention quick-reference

* Models use `ref` (string ULID) as primary key, not integer `id`
* Config from `config/config.yaml` via `Lux.config` (indifferent access)
* `.env` files loaded automatically on boot
* Inside `module Lux`, prefer `obj.is_hash?` over `obj.is_a?(Hash)`
  (`Hash` lexically resolves to `Lux::Hash`)
* Use `FOO ||=` for constants, not `FOO =`
* End files with newline, no trailing spaces on empty lines

## Testing

```bash
bundle exec rspec                       # all tests
bundle exec rspec spec/lux_tests/X.rb   # one file
lux test                                # recreate test DB + run all
```

## Status

* Version: see [`.version`](./.version)
* License: MIT, (c) 2017 Dino Reic
* GitHub: <https://github.com/dux/lux-fw>
* Author: Dino Reic ([@dux](https://github.com/dux))

Contributions welcome.
