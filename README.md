<img alt="Lux logo" width="100" height="100" src="https://i.imgur.com/Zy7DLXU.png" align="right" />

# LUX - ruby web framework

**Version 0.6.3**

A lightweight, Rack-based Ruby web framework designed for speed and simplicity.

* **Rack based** - Built on top of Rack for maximum compatibility
* **Explicit** - Avoid magic when possible for clear, predictable code
* **Fun & Learn** - Designed to make web development enjoyable
* **Dream** - Sinatra speed and memory usage with Rails-like interface

Created by @dux in 2017 - MIT License

## Installation

First, make sure you have `ruby 3.0+` installed.

```bash
gem install lux-fw
```

## Quick Start

Create a new Lux application:

```bash
lux new my-app
cd my-app
bundle install
```

Start the development server:

```bash
bundle exec lux s
```

Your app will be available at `http://localhost:3000`

Look at the generated code and play with it!


## Framework Features

Lux provides a complete web development stack with the following features:

* **Fast & Lightweight** - Minimal overhead with optimal memory usage
* **Explicit Routing** - Clear, predictable routing system
* **Component-Based** - Modular architecture with pluggable components
* **Built-in Caching** - Support for memory and memcached caching
* **Email Support** - Integrated mailer built on the mail gem
* **Template Engine** - HAML support out of the box via Tilt
* **Session Management** - JWT-based encrypted sessions
* **Error Handling** - Comprehensive error handling and logging
* **CLI Tools** - Rich command-line interface for development
* **Testing** - RSpec support included

## Project Structure

```
lux-fw/
├── bin/              # CLI commands and executables
├── lib/
│   ├── lux/          # Core framework modules
│   │   ├── application/   # Application routing and configuration
│   │   ├── cache/         # Caching implementations
│   │   ├── config/        # Configuration management
│   │   ├── controller/    # Request controllers
│   │   ├── current/       # Request context (session, cookies, etc.)
│   │   ├── environment/   # Environment detection and helpers
│   │   ├── error/         # Error handling
│   │   ├── logger/        # Logging adapter
│   │   ├── mailer/        # Email sending
│   │   ├── plugin/        # Plugin system
│   │   ├── render/        # Template rendering
│   │   ├── response/      # HTTP response handling
│   │   └── template/      # Template engine
│   ├── overload/      # Ruby core class extensions
│   ├── common/        # Common utilities
│   └── loader.rb      # Framework loader
├── misc/             # Demo app and configuration examples
├── plugins/          # Framework plugins
├── spec/             # Test suite
└── tasks/            # Rake tasks
```

## Dependencies

Lux requires the following key dependencies:

* **rack** - Web server interface
* **haml** - Template engine (pulls in tilt)
* **mail** - Email sending
* **sequel_pg** - PostgreSQL ORM
* **jwt** - Session encryption
* **thor** - CLI tools
* **amazing_print** - Debug output

See `lux-fw.gemspec` for the complete list.

## Lux module

Main `Lux` module provides useful utility methods:

```ruby
Lux.root     # Pathname to application root
Lux.fw_root  # Pathname to lux gem root
Lux.speed {} # execute block and return speed in ms
Lux.info     # show console info in magenta
Lux.run      # run a command on a server and log it
Lux.die      # stop execution of a program and log
Lux.call env # Main rack entry point
Lux.delay    # Execute block in background thread
Lux.log      # Logging helper
Lux.logger   # Named logger instance
```


## Components

Automatically loaded



* [Lux.app (Lux::Application)](#application) &sdot; [&rarr;](./lib/lux/application)
* [Lux.cache (Lux::Cache)](#cache) &sdot; [&rarr;](./lib/lux/cache)
* [Lux::Controller](#controller) &sdot; [&rarr;](./lib/lux/controller)
* [Lux.current (Lux::Current)](#current) &sdot; [&rarr;](./lib/lux/current)
* [Lux.db (Lux::Db)](#database-luxdb) &sdot; [&rarr;](./lib/lux/db)
* [Lux.env (Lux::Environment)](#environment) &sdot; [&rarr;](./lib/lux/environment)
* [Lux.error (Lux::Error)](#error) &sdot; [&rarr;](./lib/lux/error)
* [Lux.logger](#logger) &sdot; [&rarr;](./lib/lux/logger)
* [Lux::Mailer](#mailer) &sdot; [&rarr;](./lib/lux/mailer)
* [Lux.plugin (Lux::Plugin)](#plugin) &sdot; [&rarr;](./lib/lux/plugin)
* [Lux.render](#render) &sdot; [&rarr;](./lib/lux/render)
* [Lux.current.response (Lux::Response)](#response) &sdot; [&rarr;](./lib/lux/response)
* [Lux::Template](#template) &sdot; [&rarr;](./lib/lux/template)
* [Lux::Config](#config) &sdot; [&rarr;](./lib/lux/config)


### Database (Lux::Db)

Lux provides built-in database connection management via `Lux::Db`. Databases are configured in `config/config.yaml` under the `db:` key.

```yaml
# config/config.yaml
default:
  # simple form - single main database
  db: postgresql://localhost/myapp

  # or hash form - multiple named databases
  db:
    main: postgresql://localhost/myapp
    log: postgresql://localhost/myapp_log

production:
  db:
    main: postgres://user:pass@host:5432/myapp
```

ENV overrides: `DB_MAIN`, `DB_LOG`, etc. For backwards compat `DB_URL` resolves as `:main`.

```ruby
# Access databases
Lux.db              # Sequel::Database for :main
Lux.db(:log)        # Sequel::Database for :log
DB                   # lazy proxy to Lux.db(:main)

# Management
Lux::Db.connections      # all active Sequel::Database instances
Lux::Db.url_for(:main)  # resolved URL string
Lux::Db.configured_names # [:main, :log] from config
Lux::Db.disconnect_all
```

Connections are created lazily on first access. On boot (`Lux.plugin :db`), all configured databases are connected eagerly with error reporting.

Rake tasks: `db:info`, `db:create`, `db:drop`, `db:am` (auto-migrate), `db:backup`, `db:restore`, `db:seed`, `db:console`.


### Plugin System

Lux includes a plugin system for extending functionality:

```ruby
# Load a plugin from framework plugins directory
Lux.plugin :api

# Load a plugin from a custom path
Lux.plugin name: :my_plugin, folder: './plugins/my_plugin'

# Load all Ruby files in a plugin directory
Lux.plugin './path/to/plugin'

# Get loaded plugin info
Lux.plugin.get(:api)
Lux.plugin.loaded
Lux.plugin.keys
```

Plugins are loaded from the `plugins/` directory in the framework root and can be organized by namespace.



&nbsp;
<a name="application"></a>
## Lux.app (Lux::Application)

Main application controller and router

* catches errors and dispatches `:error` to the active controller (every controller inherits a default `error` action from `Lux::Controller`; override per controller for custom rendering)
* calls `before`, `routes` and `after` class filters on every request

#### Instance methods

Top-level DSL inside `Lux.app do ... end` — no `routes do` wrapper required.
`map`, `root`, `match`, `subdomain`, `mount`, `favicon`, `plugin_route`, and the
HTTP method predicates (`get?`, `post?`, etc.) all register routes callbacks
automatically. `routes do ... end` is still supported when you need a single
block for runtime conditionals (`if user`, `unless get?`, ...).

* `map 'foo'` - match `/foo`, dispatch resourcefully to `FooController` (see action table below)
* `map 'foo#bar'` - match `/foo`, explicit dispatch to `FooController#bar`
* `map 'a', 'foo'` / `map a: 'foo'` / `map a: :foo` - all equivalent: match `/a`, resourceful dispatch to `FooController`
* `map 'foo' do ... end` - match `/foo`, enter scope, run block (instance-exec'd at request time so inner `map` works)
* `map '/abs/:var' => 'main#foo'` - absolute path match with `:var` captured into params
* `map [:foo, :bar] => 'root'` - match either, dispatch to RootController
* `root 'main'` - matches when there's no further path segment
* `call 'foo'` / `call 'foo#bar'` - unconditional dispatch (used inside `rescue_from` blocks)

#### Resourceful action resolution

`map 'foo'` and friends pick an action from what's left in the route cursor
after consuming the matched segment. Combine with `nav.path(:ref) { ... }` in a
`before` filter to canonicalize ID segments to the `:ref` symbol:

```ruby
before do
  nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
end
```

| URL                         | action      | nav.ref |
|-----------------------------|-------------|--------|
| `/boards`                   | `:root`     | nil    |
| `/boards/edit`              | `:edit`     | nil    |
| `/boards/new`               | `:new`      | nil    |
| `/boards/123`               | `:show_ref` | "123"  |
| `/boards/123/edit`          | `:edit_ref` | "123"  |
| `/boards/users/123/edit`    | `:edit_ref` | "123"  |
| `/boards/foo/bar`           | `:foo`      | nil    |
| `/boards/123/foo/bar`       | `:foo_ref`  | "123"  |

Rule summary: empty remaining → `:root`. Only `:ref` → `:show_ref`. 2+ segments
→ first non-`:ref` after position 0. If any `:ref` is in the remaining path, the
resolved action gets a `_ref` suffix.

The controller declares ref-bearing actions inside a `ref do ... end` block
(see [Controller](#controller) section). Template lookup probes `show_ref.haml`
first and falls back to `show.haml`, so you can share a template or have a
dedicated ref-only one.

#### Class filters

There are a few route filters
* `config`      # pre boot app config
* `boot`        # after rack app boot (web only)
* `before`      # before any page load
* `routes`      # routes resolve (legacy block form; top-level DSL is preferred)
* `after`       # after any page load

Errors raised anywhere in the routing/action pipeline are caught by `Application#render_error`, which dispatches the `:error` action to whichever controller was active. Every controller inherits a default `error` from `Lux::Controller`; override on any controller (e.g. `MainController#error`, `Api::BaseController#error`) for custom rendering.


#### Router example

```ruby
Lux.app do

  def api_router
    Lux.error.forbidden 'Only POST requests are allowed' if Lux.env.prod? && !post?
    Lux::Api.call nav.path
  end

  before do
    check_subdomain
    nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
  end

  rescue_from do |err|
    call '%s#error' % [user ? :main : :promo]
  end

  ###

  root 'main'                                 # / -> MainController#root
  map about: 'static#about' if get?           # /about -> Static#about (GET only)
  post? { map api: :api_router }              # /api -> :api_router method (POST)
  map '/foo/:bar/baz' => 'main#foo'           # absolute path with capture

  map 'boards'                                # resourceful BoardsController
  map 'users'                                 # resourceful UsersController

  map 'admin' do                              # scope at /admin
    map 'users', 'admin/users'                # /admin/users -> Admin::UsersController
    map 'reports#monthly'                     # /admin/reports -> Admin::Reports#monthly
  end
end
```

#### Controller cursor: `lux.route`

`nav.path` is the canonical request path. The router maintains its own cursor
on `lux.route` (also accessible as `current.route`) so routing doesn't mutate
nav. Inside a `map 'admin' do ... end` block, `lux.route.path` is the slice
after `admin` was consumed; `nav.path` is still the full request path.

* `lux.route.path`     - remaining path after consumed segments
* `lux.route.root`     - first remaining segment
* `lux.route.child`    - second remaining segment
* `lux.route.consumed` - segments before the cursor


#### Config for application

```ruby
Lux.config.on_reload_code do
  $live_require_check ||= Time.now

  watched_files = $LOADED_FEATURES
    .reject { |f| f.include?('/.') }
    .select { |f| File.exist?(f) && File.mtime(f) > $live_require_check }

  for file in watched_files
    Lux.log ' Reloaded: %s' % file.sub(Lux.root.to_s, '.').yellow
    load file
  end

  $live_require_check = Time.now
end

```



&nbsp;
<a name="cache"></a>
## Lux.cache (Lux::Cache)

Simplifed caching interface, similar to Rails.

Should be configured in `./config/initializers/cache.rb`

```ruby
# init
Lux::Cache.server # defauls to memory
Lux::Cache.server = :memcached
Lux::Cache.server = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })

# read cache
Lux.cache.read key
Lux.cache.get key

# multi read
Lux.cache.read_multi(*args)
Lux.cache.get_multi(*args)

# write
Lux.cache.write(key, data, ttl=nil)
Lux.cache.set(key, data, ttl=nil)

# delete
Lux.cache.delete(key, data=nil)

# fetch or set
Lux.cache.fetch(key, ttl: 60) do
  # ...
end

Lux.cache.is_available?

# Generate cache key
# You can put anything in args and if it responds to :id, :updated_at, :created_at
# those values will be added to keys list
Lux.cache.generate_key *args
Lux.cache.generate_key(caller.first, User, Product.find(3), 'data')
```




&nbsp;
<a name="controller"></a>
## Lux::Controller

Similar to Rails Controllers

* `before`, `before_action`, `before_render` and `after` class callbacks supported
* default `error` action inherited from `Lux::Controller` — override per controller for custom error rendering (Application dispatches to it on raise)
* calls templates as default action, behaves as Rails controller.

```ruby
class RootController < ApplicationController
  # action to perform before
  before do
    @org = Org.find @org_id if @org_id
    # ...
  end
  # action to perform before

  before_action do |action_name|
    next if action_name == :root
    # ...
  end

  template_location './app/views' # default

  ###

  mock :new # mock `new` action

  # /<controller> with no further segment -> :root
  def root
    render text: 'Hello world'
  end

  def foo
    # renders ./app/views/root/foo.(haml, erb)
  end

  def baz
    send_file local_file, file_name: 'local.txt'
  end

  def bar
    render json: { data: 'Bar text' }
  end

  # Ref-bearing actions (URLs with an ID segment) live inside `ref do`.
  # Each `def NAME` is registered as `NAME_ref`. Template lookup tries
  # `show_ref.haml` first, then falls back to `show.haml`, so you can
  # share a single template or have dedicated ref-only one when needed.
  ref do
    def show       # /root/abc-123        -> :show_ref, nav.ref = "123"
      @item = Item.find(nav.ref)
    end

    def edit       # /root/abc-123/edit   -> :edit_ref
      @item = Item.find(nav.ref)
    end
  end

  def transfer
    # transfer to :baz
    action :baz

    # transfer to Another::Foo#bar
    action 'another/foo#bar'
  end
end
```

Render method can accept numerous parameters

```ruby
class MainController
  def foo
    render text: 'foo'
    render plain: 'foo'
    render html: '<html>...'
    render json: {}
    render javascript: '...'
    render template: false, content_type: :text
    render template: './some/template.haml', data: @template_data

    # helpers
    helper.link_to # MainHelper.link_to
    helper(:bar)   # BarHelper.link_to

    respond_to :js do ...
    respond_to do |format|
      case format
      when :js
        # ...
      end
  end
```

Definable callbacks

```ruby
before do ...        # before all
before_action do ... # before action
before_render do ... # before render
after do ...         # after all
```

Definable class variables

```ruby
# define master layout
# string is template, symbol is method pointer and lambda is lambda
layout './some/layout.haml'

# define helper contest, by defult derived from class name
helper :global

# custom template root instead calcualted one
template_root './apps/admin/views'
```

#### action_missing

Called when a controller action is not found. Default implementation looks for a matching template file and renders it if found (requires `Lux.config.use_autoroutes` to be enabled). Can be overridden in controllers for custom fallback logic.




&nbsp;
<a name="current"></a>
## Lux.current (Lux::Current)

Lux handles state of the app in the single object, stored in `Thread.current`, available everywhere.

You are not forced to use this object, but you can if you want to.

```ruby
current.session         # session, encoded in cookie
current.locale          # locale, default nil
current.request         # Rack request
current.response        # Lux response object
current.nav             # lux nav object
current.cookies         # Rack cookies
current.can_clear_cache # set to true if user can force refresh cache
current.var             # CleaHash to store global variables
current[:user]          # current.var.user
current.uid             # new unique ID in a page, per response
current.secure_token    # Get or check current session secure token
current.ip              # Client IP address
current.host            # Current host
current.robot?          # Bot detection
current.mobile?         # Mobile device detection

# Execute only once in current scope
current.once { @data }
current.once(key, @data)

# Cache in current response scope
current.cache(key) {}

# Encrypt/decrypt in request scope
current.encrypt(data)
current.decrypt(token)

# Execute block in background thread
current.delay { ... }

# Set current.can_clear_cache = true if user is able to clear cache with SHIFT+refresh
current.no_cache?              # false
current.can_clear_cache = true
current.no_cache?              # true if env['HTTP_CACHE_CONTROL'] == 'no-cache'


```




&nbsp;
<a name="nav"></a>
## Lux.current.nav (Lux::Application::Nav)

`nav` is the **canonical request path** object, accessible as `nav` inside
routes/controllers or `current.nav` anywhere. Routing inspects `nav` but does
not consume it — for the router cursor see `lux.route` above.

Built on top of `request.path` and `request.host`, it parses path segments,
format, and the host into domain/subdomain parts. The subdomain is TLD-aware
(handles two-part TLDs like `co.uk`, `com.au`).

```ruby
# path segments
nav.root          # first path segment
nav.child         # second path segment
nav.path          # canonical path array
nav.path = []     # set path
nav[0]            # canonical path segment by index (reflects :ref rewrites)
nav.last          # last path segment
nav.to_s          # joined path

# host parts (derived from request.host)
nav.domain        # "authcog.com" for app.authcog.com
nav.subdomain     # "app" for app.authcog.com, "" for bare domain, nil for IP host
nav.base          # scheme + host + port, e.g. "http://app.lvh.me:3000"

# format / locale (canonicalization - both consume their segment from nav.path)
nav.format        # :html, :json, ... (parsed from .ext suffix)
nav.locale { |seg| seg.length == 2 ? seg : nil } # consume locale path segment

# url helpers
nav.url           # Url.current
nav.url(foo: 1)   # current URL with ?foo=1 merged
nav.pathname               # "/users/profile" from canonical nav.path
nav.pathname(has: 'edit')  # true if path contains "/edit"
nav.pathname(ends: 'edit') # true if path ends with "/edit"

# redirect helpers (use in `before` filters)
nav.remove_www             # redirect www.foo.bar -> foo.bar
nav.rename_domain 'localhost', 'lvh.me'

# ref capture: classify path segments as :ref, store extracted values in nav.refs.
# Block returns truthy (value or true) to mark a segment; nil/false to leave alone.
# Already-:ref symbols from prior calls are skipped (idempotent).
nav.path :ref do |el|
  Ulid.is?(el) ? el : nil
end
nav.ref   # first captured ref
nav.refs  # all captured refs (spatial order)
```

`nav.shift` / `nav.unshift` / `nav.original` were removed when the router stopped
mutating `nav.path`. If you need a router-local cursor use `lux.route.*`; if you
need the raw request URL use `request.path`.

Subdomain-based routing example:

```ruby
Lux.app do
  case nav.subdomain
  when nil, ''   then call 'promo#auto_render'
  when 'app'     then call 'main#call'
  when 'admin'   then call 'admin#call'
  else                forbid!('Unknown subdomain')
  end
end
```



&nbsp;
## Lux.delay

Simplified access to delayed job operations.

In default mode when you pass a block, it will execute it in a new Thread, but in the same context it previously was.

```ruby
Lux.delay do
  UserMailer.wellcome(@user).deliver
end
```



&nbsp;
<a name="environment"></a>
## Lux.env (Lux::Environment)

Module provides access to environment settings.

Three valid environments are supported: `development`, `production`, `test` (set via `RACK_ENV` or `LUX_ENV`).

```ruby
Lux.env.development? # true when NOT production (includes test)
Lux.env.production?  # true only in production
Lux.env.test?        # true for test or when run via rspec
Lux.env.web?         # true when running under Rack/Puma
Lux.env.cli?         # true when NOT running as web server
Lux.env.rake?        # true when run via rake
Lux.env.live?        # true when ENV['LUX_LIVE'] == 'true'
Lux.env.local?       # inverse of live?
Lux.env.reload?      # true when LUX_ENV includes 'r' flag
Lux.env.log?         # true when LUX_ENV includes 'l' flag

# aliases
Lux.env.dev?  # Lux.env.development?
Lux.env.prod? # Lux.env.production?

# comparison
Lux.env == :dev
```

Note: `reload` and `log` are flags within `LUX_ENV`, not separate environment modes.
The `lux ss` command sets `LUX_ENV=le` (log + errors).




&nbsp;
<a name="error"></a>
## Lux.error (Lux::Error)

Error handling module.

#### HTTP Error Helpers

```ruby
# 400: for bad parameter request
Lux.error.bad_request message

# 401: for unauthorized access
Lux.error.unauthorized message

# 402: for payment required
Lux.error.payment_required message

# 403: for forbidden access
Lux.error.forbidden message

# 404: for not found pages
Lux.error.not_found message

# 405: for method not allowed
Lux.error.method_not_allowed message

# 406: for not acceptable
Lux.error.not_acceptable message

# 500: for internal server error
Lux.error.internal_server_error message

# 501: for not implemented
Lux.error.not_implemented message
```


#### Rendering

```ruby
# HTML render style for default Lux error
Lux::Error.render(error)

# Show inline error
Lux::Error.inline(error, message)

# Format backtrace (supports html:, message:, gems: options)
Lux::Error.format(error, opts)
```


&nbsp;
<a name="logger"></a>
## Lux.logger

Lux logger is logging helper module.

* uses default [Ruby logger](https://ruby-doc.org/stdlib/libdoc/logger/rdoc/Logger.html)
* logger output path/location can be customized via `Lux.config.logger_output_location` proc
  * default outputs
    * development: screen
    * production: `./log/@name.log`
* formating style can be customized by modifing `Lux.config.logger_formater`
* logger defined via the name will be created unless exists

```ruby
##./lib/lux/config/defaults/logger.rb##

Lux.logger(:foo).info 'hello' # ./log/foo.log

# write allways to file and provide env suffix
Lux.config.logger_output_location do |name|
  './log/%s-%s.log' % [name, Lux.env]
end

Lux.logger(:bar).info 'hello' # ./log/bar-development.log
```


#### Config for logger

```ruby
# Output log format
Lux.config.logger_formater do |severity, datetime, progname, msg|
  date = datetime.utc
  msg  = '%s: %s' % [severity, msg] if severity != 'INFO'
  "[%s] %s\n" % [date, msg]
end

# Logger output
Lux.config.logger_output_location do |name|
  Lux.env.prod? || Lux.env.cli? ? './log/%s.log' % name : STDOUT
end
```

&nbsp;
<a name="mailer"></a>
## Lux::Mailer

Light wrapper arrond [ruby mailer gem](https://github.com/mikel/mail).

* before and after class methods are supported
  * before is called mail rendering started
  * after is called after rendering but just before mail is send
* similar as in rails, renders mail as any other template
  * based on ruby mail gem
    * mail_object.deliver will deliver email
    * mail_object.body will show mail body
    * mail_object.render will retrun mail object
* Mailer.forgot_password(email).deliver will
  * execute before filter
  * create mail object in Mailer class and call forgot_password method
  * render template app/views/mailer/forgot_password
  * render layout tempplate app/views/mailer/layout
  * execute after filter
  * deliver the mail

#### Example

Suggested usage

```ruby
Mailer.deliver(:email_login, 'foo@bar.baz')
Mailer.render(:email_login, 'foo@bar.baz')
```

Natively works like

```
Mailer.prepare(:email_login, 'foo@bar.baz').deliver
Mailer.prepare(:email_login, 'foo@bar.baz').body
```

Rails mode via method missing is suported

```
Mailer.email_login('foo@bar.baz').deliver
Mailer.email_login('foo@bar.baz').body
```

#### Code

```ruby
class Mailer < Lux::Mailer
  helper :mailer

  # before method call
  before do
  end

  # after method call, but before mail is sent
  after do
    mail.from = "#{App.name} <no-reply@#{Lux.config.host}>"
  end

  # raw define mail
  def raw to:, subject:, body:
    mail.subject = subject
    mail.to      = to
    mail.body    = body.as_html
  end

  # send mail as
  #   Mailer.lost_password('foo@bar.baz').deliver
  #
  # renders tamplate and layout
  #   ./app/views/mailer/lost_password.haml
  #   ./app/views/mailer/layout.haml
  def lost_password email
    mail.subject = "#{App.name} – potvrda registracije"
    mail.to      = email

    # instance variables will be pased to templaes
    @link = "#{App.http_host}/profile/password?user_hash=#{Crypt.encrypt(email)}"
  end
end
```

#### Config for mailer

```ruby
# Default mail logging
Lux.config.on_mail_send do |mail|
  Lux.logger(:email).info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
end

```



&nbsp;
<a name="plugin"></a>
## Lux.plugin (Lux::Plugin)

Plugin management

* loads plugins in selected namespace, default namespace :main
* gets plugins in selected namespace

```ruby
# load a plugin
Lux.plugin name_or_folder
Lux.plugin name: :foo, folder: '/.../...', namespace: [:main, :admin]
Lux.plugin name: :bar

# plugin folder path
Lux.plugin.folder(:foo) # /home/app/...

# Load lux plugin
Lux.plugin :db
```

### Model Associations (lux_links plugin)

The `link` method defines model associations via `_ref` columns:

```ruby
class Task < ApplicationModel
  schema do
    link :board       # DB: board_ref column + index + foreign key
  end

  link :board         # Ruby: task.board -> Board.find(board_ref)
  link :comments      # Ruby: task.comments -> Comment.where(task_ref: ref)
end
```

* `link :user` - singular, belongs_to via `user_ref` column
* `link :users` - plural, has_many via `user_refs[]` array or reverse lookup
* `link :user, class: 'OrgUser'` - custom class
* `link :user, field: 'owner_ref'` - custom field
* `Task.where_ref(@board)` - scope dataset to parent object


&nbsp;
<a name="render"></a>
## Lux.render

Render full pages and templates.

### Render full pages

As a first argument to any render method you can provide
full [Rack environment](https://www.rubydoc.info/gems/rack/Rack/Request/Env).

If you provide only local path,
[`Rack::MockRequest`](https://www.rubydoc.info/gems/rack/Rack/MockRequest) will be created.

Two ways of creating render pages are provided.

* full builder `Lux.render(@path, @full_opts)`
* helper builder with request method as method name `Lux.render.post(@path, @params_hash, @rest_of_opts)`

```ruby
# render options - all optional
opts = {
  query_string: {}
  post: {},
  body: String
  request_method: String
  session: {}
  cookies: {}
}

# when passing data directly, renders full page with all options
page = Lux.render('/about', opts)

# you can use request method prefix
page = Lux.render.post('/api/v1/orgs/list', { page_size: 100 }, rest_of_opts)
page = Lux.render.get('/search', { q: 'london' }, { session: {user_id: 1} })

page.info # gets info hash + body
# {
#   body:    '{}',
#   time:    '5ms',
#   status:  200,
#   session: { user_id: 123 }
#   headers: { ... }
# }

page.render # get only body
```


### Render templates

Renders templates, wrapper arround [ruby tilt gem](https://github.com/rtomayko/tilt).

```ruby
Lux.render.template(@scope, @template)
Lux.render.template(@scope, template: @template, layout: @layout_file)
Lux.render.template(@scope, @layout_template) { @yield_data }
```

Scope is any object in which context tmplate will be rendered.

* you can pass `self` so template has access to the same instance
  variables and methods as current scope.
* you can construct full valid helper with `Lux.template.helper(@scope, :foo, :bar)`.
  New helper class will be created from `FooHelper module and BarHelper module`,
  and it will be populated with `@scope` instance variables.

```ruby
  # HtmlHelper module or CustomModule has to define link_to method
  helper = Lux.template.helper(@instance_variables_hash, :html, :custom, ...)
  helper.link_to('foo', '#bar') # <a href="#bar">foo</a>
```

Tip: If you want to access helper mehods while in controller, just use `helper`.


### Render controllers

Render controller action without routes, pass a block to yield before action call
if you need to set up params or instance variables.

```ruby
Lux.render.controller('main/cities#foo').body
Lux.render.controller('main/cities#bar') { @city = City.last_updated }.body
```


### Render ViewCells

ViewCells are provided by `Lux::ViewCell` (see `lib/lux/view_cell/`).

```ruby
Lux.render.cell(:city, @city)
```




&nbsp;
<a name="response"></a>
## Lux.current.response (Lux::Response)

Current request response object

You can allways use `Lux.current.response` object, or accesss it as `response` inside the controller.

```ruby
# add response header
response.header 'x-blah', 123

# default is private cache: Cache-Control: private, must-revalidate, max-age=0

# explicit public cache (shared cache; suppresses Set-Cookie)
response.cache.public  = true
response.cache.max_age = 10.minutes

# shortcut for the common public-cache case
response.cache_public 10.minutes

# disable cache and session cookie for sensitive responses
response.no_store

# page status
response.status = 400

# HTTP early hints
response.early_hints link, type

# generate etag header and stop response if matching header found
response.etag *args

# halt response render and deliver page
response.halt status, body

# set or get the body
# if you set the body, response is halted
response.body = @data # set body
response.body         # @body
response.body?        # true if body present

# get or set content type
response.content_type = :js
response.content_type = :plain
response.content_type

# send flash message to current request or to the next if redirect happens
response.flash 'Bad user name or pass'
response.flash.error 'Bad user name or pass'
response.flash.info 'Login ok'

# send file to a browser
response.send_file './tmp/local/location.pdf', inline: true

# redirect the request
response.redirect_to '/foo'
response.redirect_to :back, error: 'Bad user name or pass'

# permanent redirect (301)
response.permanent_redirect_to '/new-path'

# basic http auth
response.auth do |user, pass|
  [user, pass] == ['foo', 'bar']
end
```




&nbsp;
<a name="template"></a>
## Lux::Template

Template rendering engine built on top of Tilt (loaded transitively via haml).

Supports multiple template formats including HAML, ERB, and others.

```ruby
# Render a template with a scope
Lux::Template.render(scope, './path/to/template.haml')

# Render with layout
Lux::Template.render(scope, template: './template.haml', layout: './layout.haml')

# Render with yield content
Lux::Template.render(scope, './layout.haml') { 'content to yield' }

# Create a helper with access to scope
helper = Lux::Template.helper(scope, :main)
```

### Template Helper

The helper module provides Rails-style helper functionality:

```ruby
module MainHelper
  def link_to(text, url)
    %[<a href="#{url}">#{text}</a>]
  end
end

# Use in template
helper = Lux::Template.helper(scope, :main)
helper.link_to('Home', '/')
```

Template caching is enabled in production mode for better performance.



&nbsp;
<a name="config"></a>
## Lux::Config

Configuration management system for Lux applications.

`Lux.config` returns a hash (with indifferent access) loaded from `config/config.yaml`.
`Lux.secrets` is an alias for `Lux.config`.

```ruby
# Set configuration values
Lux.config.key = value

# Get configuration values
Lux.config.key

# Get all config
Lux.config.all
```

### Default Configuration Values

```ruby
# Delay job timeout (3600 dev / 30 prod)
Lux.config.delay_timeout = 30

# Logger configuration
Lux.config.log_level = :info           # or :error
Lux.config.logger_path_mask = './log/%s.log'
Lux.config.logger_files_to_keep = 3
Lux.config.logger_file_max_size = 10_240_000

# Enable template-based routes (default: false)
Lux.config.use_autoroutes = false

# Static file serving (default: true)
Lux.config.serve_static_files = true

# Asset root path
Lux.config.asset_root = false

# Application timeout
Lux.config.app_timeout = 30

# Hooks
Lux.config.on_reload_code { ... }      # Called when code reloads
Lux.config.on_mail_send { |mail| ... } # Called when mail is sent
```

### Session Configuration

```ruby
Lux.config[:session_cookie_name]       # Cookie name
Lux.config[:session_cookie_max_age]    # Cookie max age
Lux.config[:session_forced_validity]   # Force session validity
```



&nbsp;
## Methods added to base Ruby classes

### Dir
#### Dir.folders

Get list of folders in a folder

`Dir.folders('./app/assets')`

#### Dir.files

Get all files in a folder

`Dir.files('./app/assets')`

#### Dir.find

Deep file search with filtering options.

`Dir.find('./app/assets', ext: [:js, :coffee], root: './app')`

#### Dir.require_all

Requires all found ruby files in a folder, deep search into child folders

`Dir.require_all('./app')`

### Array
#### @array.to_csv

Convert list of lists to CSV (semicolon-delimited)

#### @array.last=

Set last element of an array

#### @array.to_sentence

Convert list to sentence, Rails like

`@list.to_sentence(words_connector: ', ', two_words_connector: ' and ', last_word_connector: ', and ')`

#### @array.toggle

Toggle existence of an element in array and return true when one added

`@list.toggle(:foo)`

#### @array.random_by_string

Will return fixed element for any random string

`@list.random_by_string('foo')`

#### @array.to_ul

Convert list to HTML UL list

`@list.to_ul(:foo) # <ul class="foo"><li>...`

### Class
#### @class.descendants

Get all class descendants

`ApplicationModel.descendants # get all DB models`

### Float
#### @float.as_currency

Convert float to currency (European style)

`@sum.as_currency(pretty: false, symbol: '$')`

### Integer
#### @int.pluralize

Smart pluralization

`5.pluralize(:cat) # "5 cats"`

#### @int.to_filesize

Human-readable file size

`1024.to_filesize # "1.0 KB"`

### String
#### @str.parameterize / @str.to_url

URL-safe string (max 50 chars)

#### @str.trim

Truncate with ellipsis

`'hello world'.trim(5) # "hello&hellip;"`

#### @str.sha1 / @str.md5

Hash digests

#### @str.colorize / @str.decolorize

ANSI terminal colors

`'hello'.colorize(:green)`

## Development Server

Start the development server with:

```bash
lux s              # Start on port 3000 (default)
lux s -p 3001      # Start on specific port
lux s -p 3001-3003 # Start 3 servers with auto-restart on failure
lux s -e p         # Start in production mode
```

### Server Options

```bash
-p, --port PORT    # Port or port range (e.g., 3001-3003)
-e, --env ENV      # Environment (test, dev, prod)
-r, --rerun        # Rerun app on every file change
-o, --opt OPT      # Lux options (l=log, r=reload, e=errors)
```

### Environment Variables

```bash
PORT=3000           # Single port (default: 3000)
PORT_RANGE=3001-3003 # Port range for multi-server mode (optional)
```

Priority order: `-p` option > `PORT_RANGE` > `PORT` > default 3000

### Port Range Mode

When using a port range (via `-p` or `PORT_RANGE`), Lux starts multiple puma processes:
- Each runs in a while loop with auto-restart on failure
- 5 second delay between restarts
- All processes terminate on Ctrl+C


## Production Deployment (lux sysd)

Lux provides integrated systemd service management for production deployments.

### Setup

Add to your `.env` file:

```bash
DOMAIN=myapp.com      # Required - your domain
PORT=3000             # Single port (default: 3000)
PORT_RANGE=3000-3003  # Port range for multi-server mode (optional)
```

When `PORT_RANGE` is set, multiple puma processes are started for load balancing.
The generated nginx/caddy configs will include all ports in the upstream pool.

### Generate Config Files

```bash
lux sysd generate
```

This generates files in `./config/sysd/`:

| File | Description |
|------|-------------|
| `lux-web-{app}.service` | Systemd service for web server |
| `lux-job-{app}.service` | Systemd service for job runner |
| `caddy.conf` | Caddy reverse proxy config |
| `nginx-proxy.conf` | Nginx reverse proxy config |
| `nginx-passenger.conf` | Nginx with Passenger config |

Each file includes install instructions in the header comments.

### Service Management

```bash
lux sysd tui              # Interactive TUI for service management
lux sysd list             # List services with status
lux sysd install [name]   # Show install instructions
lux sysd start <name>     # Start service
lux sysd stop <name>      # Stop service
lux sysd restart <name>   # Restart service
lux sysd log <name>       # Follow service logs
lux sysd status [name]    # Show service status
```

### Quick Install Example

```bash
# Generate configs
lux sysd generate

# Install web service (symlink)
sudo ln -sf $(pwd)/config/sysd/lux-web-myapp.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable lux-web-myapp
sudo systemctl start lux-web-myapp

# Add Caddy config (import method)
echo "import $(pwd)/config/sysd/caddy.conf" | sudo tee -a /etc/caddy/Caddyfile
sudo systemctl reload caddy
```


## Lux Command Line

You can run command `lux` in your app home folder.

```bash
$ lux
Commands:
  lux console         # Start console
  lux evaluate        # Eval ruby string in context of Lux::Application
  lux generate        # Generate models, cells, ...
  lux help [COMMAND]  # Describe available commands or one specific command
  lux memory          # Profile memory usage
  lux new APP         # Create new Lux application
  lux render          # Render page via Lux.render "lux render /login -t TOKEN -i"
  lux secrets         # Display ENV and secrets
  lux server          # Start web server
  lux stats           # Print project stats
  lux sysd            # Manage systemd services and generate config files
```

## Testing

Lux uses RSpec for testing. Run the test suite with:

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/lux_tests/routes_spec.rb
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

The MIT License (MIT) - Copyright (c) 2017 Dino Reic

See LICENSE file for full details.

## Links

* GitHub: http://github.com/dux/lux-fw
* Author: Dino Reic (@dux) - rejotl@gmail.com
