<img alt="Lux logo" width="100" height="100" src="https://i.imgur.com/Zy7DLXU.png" align="right" />

# Lux

**A Ruby web framework that unifies the primitives an enterprise backend
actually needs - so you (and your LLM) learn one DSL and use it
everywhere.**

[Sinatra](http://sinatrarb.com/) speed and simplicity, with the features
of [Roda](https://roda.jeremyevans.net/),
[Rails](https://rubyonrails.org/), and [Hanami](https://hanamirb.org/) -
unified under a single shared DSL. Rack-based, Sequel ORM, PostgreSQL.

```bash
gem install lux-fw
lux new my-app && cd my-app && bundle exec lux s
```

### Sinatra-simple if that's all you need

```ruby
# config.ru
require 'lux-fw'

Lux do
  routes do
    map foo: 'foo#call'           # /foo -> FooController#call
    body 'Hello world, this is 404'
  end
end
```

`rackup` it and you're up. Lux scales down to one file and up to a full
enterprise backend through the same DSL.

### Standard app shape

`require 'lux-fw'` loads the framework only - no `.env`, no
`config.yaml`, no plugin loaders, no DB connect. App boot is one
explicit call: `Lux.boot!`. It resolves `LUX_ENV` / `RACK_ENV`, loads
`.env*`, runs `Bundler.require`, reads `config/config.yaml`, and fires
every configured plugin's loader (DB connect, exception logger, etc).
Idempotent.

```ruby
# config/env.rb - the canonical bootstrap
require 'bundler/setup'
require 'lux-fw'
Lux.boot!

# host-specific tweaks (config is loaded, plugins active)
Lux.config.localize = false
Dir.require_all './config/initializers'
```

```ruby
# config.ru
require_relative './config/env'
run Lux
```

CLI tasks declare `needs :app` and the `:app` task in `bin/lux` runs
`Lux.boot!` for you. Light commands like `lux mount` or `lux --help`
never call it, so they stay fast. `Lux::Application#call` also calls
`Lux.boot!` defensively on the first request, so hosts that skip
`config/env.rb` in `config.ru` still work.

## Why Lux

Enterprise backends need the same set of things: schemas, type coercion,
access policies, params validation, JSON APIs, multi-DB, background
jobs, mailers, sessions, error handling. In most frameworks these are
bolted on from different libraries with **different DSLs, different
option names, different type vocabularies**. Every new subsystem is a
new dialect.

Lux ships these as first-class modules that **share the same primitives**:

* **One schema DSL** drives params validation in controllers
  (`opt :name, String, max: 30`), API endpoints (`params do ... end`),
  model field definitions, and DB migrations.
* **One type system** (`:email`, `:uuid`, `:slug`, `:locale`, ...) is
  the vocabulary everywhere a type is named.
* **One access policy** used identically by controllers, APIs, and
  models (`@blog.can.read?`).
* **One request context** (`Lux.current`) used by everything that
  needs to know about the in-flight request.

The win is twofold:

1. **For humans:** learn `opt :email, type: :email, req: false` once -
   it works the same in a controller, an API, a schema block, a form
   helper.
2. **For LLMs:** one DSL means generated code is consistent across the
   codebase - fewer hallucinations and better completions. The framework
   self-documents via [`/sys/AGENTS.md`](./lib/lux/api/sys_api.rb) so any
   deployed app exposes its full API surface to agents.

## Framework features

* Top-level routing DSL with tree-style scoping (`map`, `root`, `subdomain`,
  `mount`, `plugin_route`, HTTP-method predicates), no `routes do` wrapper
* Controllers with the shared `opt` / `params do` schema DSL
* JSON-RPC-style APIs with auto-generated explorer, OpenAPI, Postman, and
  `/sys/AGENTS.md` for agents
* Schema + type system used identically in controllers / APIs / models /
  DB migrations
* Access policies usable from controllers, APIs, and models
* Multi-DB Sequel pool, eager-on-boot, lazy-on-access
* JWT-encrypted sessions
* Memory / Memcached / SQLite / null cache with one API
* Custom reloader that skips `Gem.path` - reload stays fast even with a
  fat Gemfile
* `Lux.defer` background threads with a clean `Lux.current` and parent
  context passed explicitly to the block
* HTML mailer + template rendering via Tilt (HAML, ERB, ...)
* Pluggable plugin system with canonical folder layout
* `lux` CLI built on [`lux-hammer`](https://github.com/dux/lux-hammer) -
  declarative tasks, typed options, namespace tree, zero runtime deps

## A taste of the unification

The same line parser handles the schema in a controller, in an API, in
a model, or in a standalone `Lux.schema` block:

```ruby
# in a controller
class UsersController < Lux::Controller
  opt :name,  String, max: 30
  opt :email, type: :email
  def create
    # current.params is already validated, coerced, undeclared keys dropped
  end
end

# in an API
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

# in a model
class User < ApplicationModel
  schema do
    name  String, max: 30
    email type: :email, index: true
  end
end
```

Same DSL. Same type vocabulary. Same option keys.

## Modules

Every sub-module under `lib/lux/<name>/` ships a `README.md` (human
docs) and an `AGENTS.md` (LLM docs).

| Module | Adapter / usage | LLM guide |
|--------|-----------------|-----------|
| [`Lux::Api`](./lib/lux/api/README.md)                   | `Lux::Api` (subclass `ApplicationApi`)     | [AGENTS](./lib/lux/api/AGENTS.md) |
| [`Lux::Application`](./lib/lux/application/README.md)   | `Lux do ... end` / `Lux.app`               | [AGENTS](./lib/lux/application/AGENTS.md) |
| [`Lux::Cache`](./lib/lux/cache/README.md)               | `Lux.cache`                                | [AGENTS](./lib/lux/cache/AGENTS.md) |
| [`Lux::Config`](./lib/lux/config/README.md)             | `Lux.config`                               | [AGENTS](./lib/lux/config/AGENTS.md) |
| [`Lux::Controller`](./lib/lux/controller/README.md)     | `class X < Lux::Controller`                | [AGENTS](./lib/lux/controller/AGENTS.md) |
| [`Lux::Current`](./lib/lux/current/README.md)           | `Lux.current` / `current` / `lux`          | [AGENTS](./lib/lux/current/AGENTS.md) |
| [`Lux::Db`](./lib/lux/db/README.md)                     | `Lux.db` / `Lux.db(:name)` / `DB`          | [AGENTS](./lib/lux/db/AGENTS.md) |
| [`Lux::Environment`](./lib/lux/environment/README.md)   | `Lux.env` / `Lux.mode` / `Lux.runtime`     | [AGENTS](./lib/lux/environment/AGENTS.md) |
| [`Lux::Error`](./lib/lux/error/README.md)               | `Lux.error` / `Lux.error.not_found`        | [AGENTS](./lib/lux/error/AGENTS.md) |
| [`Lux::Hash`](./lib/lux/hash/README.md)                 | `{}.to_lux_hash` / `Lux::Hash.new`         | [AGENTS](./lib/lux/hash/AGENTS.md) |
| [`Lux::JsonExporter`](./lib/lux/json_exporter/README.md)| `class X < Lux::JsonExporter`              | [AGENTS](./lib/lux/json_exporter/AGENTS.md) |
| [`Lux::Logger`](./lib/lux/logger/README.md)             | `Lux.log` / `Lux.logger` / `Lux.logger(:n)`| [AGENTS](./lib/lux/logger/AGENTS.md) |
| [`Lux::Mailer`](./lib/lux/mailer/README.md)             | `class Mailer < Lux::Mailer`               | [AGENTS](./lib/lux/mailer/AGENTS.md) |
| [`Lux::Plugin`](./lib/lux/plugin/README.md)             | `Lux.plugin :name`                         | [AGENTS](./lib/lux/plugin/AGENTS.md) |
| [`Lux::Policy`](./lib/lux/policy/README.md)             | `class XPolicy < Lux::Policy`              | [AGENTS](./lib/lux/policy/AGENTS.md) |
| [`Lux::Reloader`](./lib/lux/reloader/README.md)         | `Lux::Reloader.run` / `reload!`            | [AGENTS](./lib/lux/reloader/AGENTS.md) |
| [`Lux::Render`](./lib/lux/render/README.md)             | `Lux.render` / `Lux.render.get(...)`       | [AGENTS](./lib/lux/render/AGENTS.md) |
| [`Lux::Response`](./lib/lux/response/README.md)         | `response` / `Lux.current.response`        | [AGENTS](./lib/lux/response/AGENTS.md) |
| [`Lux::Schema`](./lib/lux/schema/README.md)             | `Lux.schema(:name) { ... }`                | [AGENTS](./lib/lux/schema/AGENTS.md) |
| [`Lux::Shell`](./lib/lux/shell/README.md)               | `Lux.shell.exec` / `.info` / `.error`      | [AGENTS](./lib/lux/shell/AGENTS.md) |
| [`Lux::Template`](./lib/lux/template/README.md)         | `Lux::Template.render`                     | [AGENTS](./lib/lux/template/AGENTS.md) |
| [`Lux::Type`](./lib/lux/type/README.md)                 | `Lux::Type.load(:email)` / type symbols    | [AGENTS](./lib/lux/type/AGENTS.md) |
| [`Lux::ViewCell`](./lib/lux/view_cell/README.md)        | `class X < Lux::ViewCell`                  | [AGENTS](./lib/lux/view_cell/AGENTS.md) |

### Lux::Api

JSON-RPC-ish API classes. Shares the `params do` DSL with controllers
and the schema layer. Auto-mounts `/sys/web` (interactive explorer),
`/sys/openapi.json`, `/sys/postman.json`, `/sys/AGENTS.md`.

```ruby
class UsersApi < ApplicationApi
  desc 'Create a user'
  params do
    name  String, max: 30
    email type: :email
  end
  def create
    User.create!(@api.params.to_h)
  end
end
```

### Lux::Application

Router and request lifecycle. Lifecycle callbacks at the top level of
`Lux do ... end`; routing DSL inside `routes do ... end`.

```ruby
Lux do
  before do
    nav.path(:ref) { |el| el =~ /\A\d+\z/ ? el : nil }
  end

  # post-render: expand T[key.path] placeholders to real translations
  after do
    response.body { |b| b.gsub(/T\[([\w.]+)\]/) { Translation.fetch($1) } }
  end

  rescue_from do |err|
    call 'main#error'                          # MainController#error
  end

  routes do
    root 'main'
    map about: 'static#about' if get?
    map 'admin' do
      map users: 'admin/users'
    end
    mount ApiApp => '/api'
  end
end
```

### Lux::Cache

Unified cache API across memory / memcached / sqlite / null backends.

```ruby
Lux.cache.fetch('users/count', ttl: 60) { User.count }
Lux.cache.delete('users/count')
Lux.cache.lock('task', 3) { do_it }
```

### Lux::Config

YAML config + `.env` loader + lifecycle hooks. Indifferent access.

```ruby
Lux.config.host                        # read from config/config.yaml
Lux.config.app_timeout = 30            # write at runtime
Lux.config.on_mail_send { |m| ... }    # lifecycle hook
```

### Lux::Controller

HTTP controllers. Rails-shaped lifecycle; params declared with the
shared `opt` / `params do` DSL.

```ruby
class BoardsController < Lux::Controller
  before { @user = User.current or Lux.error.unauthorized }

  opt :name,  String, max: 30
  opt :tags?, [String]
  def create
    @user.boards.create!(current.params.to_h)
  end
end
```

### Lux::Current

Thread-local request context. One per request, accessible as
`Lux.current`, `current`, or `lux`.

```ruby
current.params                         # validated/coerced params
current.session[:user_id] = @user.id   # JWT-encrypted session
current[:account] = @user.account      # request-scoped bag
current.cache(:billing) { ... }        # request-scoped memo
Lux.defer { Mailer.deliver(...) }  # bg thread, clean Lux.current inside
```

### Lux::Db

Multi-DB Sequel pool. `DB` is a lazy proxy to `Lux.db(:main)`.

```ruby
Lux.db                                 # :main Sequel::Database
Lux.db(:log)                           # any named connection
DB[:users].where(active: true).all     # via proxy
```

### Lux::Environment

Three orthogonal facets: name, behavior, runtime.

```ruby
Lux.env.production?                    # name (dev/prod/test)
Lux.mode.log?                          # behavior toggle (log/errors/reload)
Lux.runtime.web?                       # process kind (web/cli/rake)
```

### Lux::Error

Thin exception class plus raise helpers that also set the response
status.

```ruby
Lux.error.not_found                    # 404
Lux.error.forbidden 'no access'        # 403
Lux.error(418, "I'm a teapot")         # arbitrary status
Lux::Error.render(exception)           # last-resort rendering
```

### Lux::Hash

Hash with indifferent access. Used everywhere the framework returns or
accepts flexible-key data.

```ruby
h = { 'name' => 'Dux' }.to_lux_hash
h[:name] == h['name'] == h.name        # all 'Dux'
```

### Lux::JsonExporter

Structured JSON export from any object. One exporter class per model,
multiple shapes.

```ruby
class UserExporter < Lux::JsonExporter
  define do
    json[:ref]  = model.ref
    json[:name] = model.name
  end
end

UserExporter.export(@user)
```

### Lux::Logger

Default logger + named loggers with rotation.

```ruby
Lux.log 'request handled'              # info shortcut
Lux.logger.error 'boom'
Lux.logger(:audit).info 'user logged in'   # -> ./log/audit.log
```

### Lux::Mailer

Mail composition + template rendering, wrapper over the `mail` gem.

```ruby
class Mailer < Lux::Mailer
  def welcome user
    mail.subject = 'Welcome'
    mail.to      = user.email
    @user        = user
  end
end

Mailer.deliver(:welcome, user)
```

### Lux::Plugin

Plugin loader with canonical folder layout.

```ruby
Lux.plugin :db, :authcog, :html
Lux.plugin.get(:db).folder             # filesystem path of a loaded plugin
```

### Lux::Policy

Access policies usable from models, controllers, and APIs.

```ruby
class BlogPolicy < Lux::Policy
  def read?
    model.created_by == user.id
  end
end

@blog.can.read?                         # bool
@blog.can.read!                         # raises Lux::Policy::Error on fail
authorize @blog.can.read?               # in a controller: 403 on fail
```

### Lux::Reloader

Custom code reloader that skips installed gems. Fires per-request in
dev/web.

```ruby
Lux::Reloader.run                       # explicit
reload!                                 # console helper
```

### Lux::Render

Render pages, controllers, templates, view cells - with or without an
HTTP server.

```ruby
Lux.render.get('/about').body           # full-page render via router
Lux.render.controller('users#show') { @user = User.first }.body
Lux.render.template(self, './app/views/welcome.haml')
Lux.render.cell(:user, self).avatar(@user)
```

### Lux::Response

HTTP response builder. Default cache is private; public is opt-in.

```ruby
response.status 201
response.header 'x-app', 'lux'
response.cache_public 10.minutes
response.etag :report, Report.max(:updated_at)
response.send_file './tmp/report.pdf', inline: true
```

### Lux::Schema

The schema DSL at the heart of the framework - shared by controllers,
APIs, models, and migrations.

```ruby
Lux.schema :user do
  name  String, max: 30
  email type: :email, index: true
  age   Integer, min: 13, max: 130
end

Lux.schema(:user).validate(params, strict: true)
```

### Lux::Template

Tilt-based template rendering with helper module mixing.

```ruby
Lux::Template.render(self, './app/views/users/show.haml')
helper = Lux::Template.helper({ '@user' => @user }, :html, :main)
helper.link_to 'Home', '/'
```

### Lux::Type

Named types - the type vocabulary the rest of the framework uses.
Plug-in new types under `lib/lux/type/types/`.

```ruby
opt :email,   type: :email             # in a controller or API
opt :country, type: :country
opt :id,      type: :uuid

Lux::Type.load(:email).new('foo@bar.baz').get
```

### Lux::ViewCell

Reusable view components. One class per cell; one template per method.

```ruby
class UserCell < ApplicationCell
  def card
    render :card
  end
end

UserCell.new.card                       # standalone
Lux.render.cell(:user, self).card       # via Lux.render
# in HAML:                              = cell(:user).card
```

## Plugins (`plugins/`)

Optional features, loaded with `Lux.plugin :name`. Canonical layout: see
[`Lux::Plugin`](./lib/lux/plugin/README.md).

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

## Hammer (the CLI engine)

The `lux` executable is built on [`lux-hammer`](https://github.com/dux/lux-hammer) -
a small declarative CLI builder. Every `lux <cmd>` is a hammer task,
discovered at startup from:

* `bin/cli/*_hammer.rb` (framework tasks)
* `plugins/<name>/Hammerfile` and `plugins/<name>/hammer/*_hammer.rb`
  (per-plugin tasks - only loaded if the plugin is configured in
  `config/config.yaml`)
* `./lib/tasks/*_hammer.rb` (project tasks)
* `./Hammerfile` (ad-hoc project tasks)

### Root functions inside a task

A hammer task is a `task :name do ... end` block. Inside it:

| Function | Purpose |
|----------|---------|
| `desc 'text'`           | one-line description (shown in `lux help`) |
| `example 'cmd args'`    | one or more usage examples for `lux help <cmd>` |
| `opt :name, ...`        | typed option: `type:`, `default:`, `alias:`, `placeholder:`, `desc:` |
| `alt :other`            | command alias (`lux foo` -> `lux other`) |
| `needs :env`            | prerequisite tasks (e.g. load `./config/env`) |
| `proc do \|opts\| ... end` | the body; `opts[:args]` for positional, `opts[:name]` for declared opts |

```ruby
# bin/cli/foo_hammer.rb (or plugins/<name>/hammer/foo_hammer.rb)
task :foo do
  desc 'Run foo with options'
  example 'foo -v --env=prod some-arg'
  needs :env

  opt :verbose, alias: :v, type: :boolean, default: false, desc: 'verbose output'
  opt :env,     alias: :e, default: 'dev', desc: 'environment'

  proc do |opts|
    say.green "running foo in #{opts[:env]} verbose=#{opts[:verbose]}"
    say "args: #{opts[:args].inspect}"
  end
end
```

### Namespaces

```ruby
namespace :db do
  task :migrate do
    desc 'Run pending migrations'
    proc { |_| Lux::Db.migrate! }
  end

  namespace :seed do
    task :load do
      desc 'Load seed data'
      proc { |_| load './db/seeds/all.rb' }
    end
  end
end
```

Invoke as `lux db:migrate` / `lux db:seed:load`.

### `say` helper (inside a `proc do |opts|`)

```ruby
say 'plain'
say.green 'success'
say.red 'error'
say.yellow 'warning'
say.blue 'info'
```

Hammer's full source: <https://github.com/dux/lux-hammer>

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
