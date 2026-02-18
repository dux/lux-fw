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
* **Built-in Caching** - Support for memory, memcached, and SQLite caching
* **Email Support** - Integrated mailer built on the mail gem
* **Template Engine** - HAML support out of the box with Tilt
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
│   │   ├── mailer/        # Email sending
│   │   ├── plugin/        # Plugin system
│   │   ├── render/        # Template rendering
│   │   ├── response/      # HTTP response handling
│   │   └── template/      # Template engine
│   ├── overload/      # Ruby core class extensions
│   ├── common/        # Common utilities
│   └── loader.rb      # Framework loader
├── misc/             # Demo app and configuration examples
├── spec/             # Test suite
└── tasks/            # Rake tasks
```

## Dependencies

Lux requires the following key dependencies:

* **rack** - Web server interface
* **haml** - Template engine
* **mail** - Email sending
* **sequel_pg** - PostgreSQL ORM
* **jwt** - Session encryption
* **thor** - CLI tools
* **colorize** - Terminal coloring
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
```


## Components

Automatically loaded



* [Lux.app (Lux::Application)](#application) &sdot; [&rarr;](./lib/lux/application)
* [Lux.cache (Lux::Cache)](#cache) &sdot; [&rarr;](./lib/lux/cache)
* [Lux::Controller](#controller) &sdot; [&rarr;](./lib/lux/controller)
* [Lux.current (Lux::Current)](#current) &sdot; [&rarr;](./lib/lux/current)
* [Lux.delay (Lux::DelayedJob)](#delay) &sdot; [&rarr;](./lib/lux/delay)
* [Lux.env (Lux::Environment)](#environment) &sdot; [&rarr;](./lib/lux/environment)
* [Lux.error (Lux::Error)](#error) &sdot; [&rarr;](./lib/lux/error)
* [Lux.logger](#logger) &sdot; [&rarr;](./lib/lux/logger)
* [Lux::Mailer](#mailer) &sdot; [&rarr;](./lib/lux/mailer)
* [Lux.plugin (Lux::Plugin)](#plugin) &sdot; [&rarr;](./lib/lux/plugin)
* [Lux.render](#render) &sdot; [&rarr;](./lib/lux/render)
* [Lux.current.response (Lux::Response)](#response) &sdot; [&rarr;](./lib/lux/response)
* [Lux.secrets (Lux::Secrets)](#secrets) &sdot; [&rarr;](./lib/lux/secrets)
* [Lux::ViewCell](#view_cell) &sdot; [&rarr;](./lib/lux/view_cell)
* [Lux::Template](#template) &sdot; [&rarr;](./lib/lux/template)
* [Lux::Config](#config) &sdot; [&rarr;](./lib/lux/config)


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

* can capture errors with `rescue_from` class method
* calls `before`, `routes` and `after` class filters on every request

#### Instance methods

* routes requests to controllers via `map`, `root` and `call` methods
* taget can be 3 object variants, look at the `call` example
* `map` maps requests to controller actions
  * `map.about => 'main#about' if get?` -> map '/about' to `MainControler#about` if request is `GET`
  * `map about: 'main#about'` -> map '/about' to `MainControler#about`
* `root` will call only for root
  * `map.about => 'main#about' if get?` -> map '/about' to `MainControler#about` if request is `GET`
  * `map about: 'main#about'` -> map '/about' to `MainControler#about`
* `call` calls specific controller action inside call - stops routing parsing
  * `call 'main/links#index'` - call `Main::LinksController#index`
  * `call [Main::LinksController, :index]` - call `Main::LinksController#index`
  * `call -> { [200, {}, ['OK']]}` - return HTTP 200 - OK

#### Class filters

There are a few route filters
* `config`      # pre boot app config
* `boot`        # after rack app boot (web only)
* `info`        # called by "lux config" cli
* `before`      # before any page load
* `routes`      # routes resolve
* `after`       # after any page load
* `rescue_from` # on routing error


#### Router example

For Lux routing you need to know only few things

* `get?`, `post?`, `delete?`, ... will be true of false based HTTP_REQUEST type
  * `get? { @exec_if_true }` works as well
* `map` method accepts block that wraps map calls.
  * `map :city do ...` will call `city_map` method. it has to return falsey if no match
  * `map 'city' do ...` will check if we are under `/city/*` nav namespace

```ruby
Lux.app do

  def api_router
    error :forbiden, 'Only POST requests are allowed' if Lux.env.prod? && !post?
    Lux::Api.call nav.path
  end

  before do
    check_subdomain
  end

  after do
    error 404
  end

  rescue_from :all do |error|
    case error
    when PG::ConnectionBad
      # ...
    when Lux::Error
      # ...
    else
  end

  ###

  routes do
    # we show on root method, that target can be multiple object types, 5 variants
    # this target is valid target for any of the follwing methods: get, post, map, call, root
    root [RootController, :index] # calls RootController#index
    root 'root#index'             # calls RootController#index
    root 'root'                   # calls RootController#call

    root 'main/root'

    # simple route, only for GET
    map.about 'static#about' if get?

    # execute blok if request_type is POST
    post? do
      # map "/api" to "api_router" method
      map.api :api_router
      # or
      map api: :api_router
    end

    # map "/foo/dux/baz" route to MainController#foo with params[:bar] == 'dux'
    map '/foo/:bar/baz'  => 'main#foo'

    # call method "city_map", if it returns true, proceed
    map :city do
      # call MainController#city if request.method == 'GET'
      map 'main#city'
    end

    # if we match '/foo' route
    map 'foo' do
      # call MainController#foo with params[:bar] == '...'
      map '/baz/:bar' => 'main#foo'
    end
  end
end
```


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

* `before`, `before_action`, `after` and `rescue_from` class methods supportd
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
    next if action_name == :index
    # ...
  end

  template_location './app/views' # default

  ###

  mock :show # mock `show` action

  def index
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

# Execute only once in current scope
current.once { @data }
current.once(key, @data)

# Cache in current response scope
current.cache(key) {}

# Set current.can_clear_cache = true if user is able to clear cache with SHIFT+refresh
current.no_cache?              # false
current.can_clear_cache = true
current.no_cache?              # true if env['HTTP_CACHE_CONTROL'] == 'no-cache'


```




&nbsp;
<a name="delay"></a>
## Lux.delay (Lux::DelayedJob)

Simplified access to range of delayed job operations

In default mode when you pass a block, it will execute it new Thread, but in the same context it previously was.

```ruby
Lux.delay do
  UserMailer.wellcome(@user).deliver
end
```



&nbsp;
<a name="environment"></a>
## Lux.env (Lux::Environment)

Module provides access to environment settings.

```ruby
Lux.env.development? # true in development and test
Lux.env.production?  # true in production and log
Lux.env.test?        # true for test
Lux.env.log?         # true for log
Lux.env.rake?        # true if run in rake
Lux.env.cli?         # true if not run under web server

# aliases
Lux.env.dev?  # Lux.env.development?
Lux.env.prod? # Lux.env.production?
```

Lux provides 4 environment modes that are set via `ENV['RACK_ENV']` or `ENV['LUX_ENV']`:

* **development** - Development mode with debugging enabled
* **production** - Production mode optimized for performance
* **test** - Test mode (returns true for both `test?` and `development?`)
* **log** - Production mode with logging enabled (returns true for both `log?` and `production?`)

The `log` mode is activated when running the server with `bundle exec lux ss`




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

# 403: for forbidden access
Lux.error.forbidden message

# 404: for not found pages
Lux.error.not_found message

# 500: for internal server error
Lux.error.internal_server_error message
```

#### Exception Logging

Real exceptions (not `Lux::Error`) are automatically logged to `./log/exception.log`.

```ruby
# Log an exception (skips Lux::Error instances)
Lux::Error.log(error_object)

# Define custom error handler (for DB, Sentry, etc.)
Lux::Error.on_error do |error|
  # Log to database
  ExceptionLog.create(
    error_class: error.class.to_s,
    message: error.message,
    backtrace: error.backtrace&.join("\n")
  )

  # Or send to Sentry
  Sentry.capture_exception(error)
end
```

#### Rendering

```ruby
# HTML render style for default Lux error
Lux::Error.render(error)

# Show inline error
Lux::Error.inline(error, message)
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





&nbsp;
<a name="response"></a>
## Lux.current.response (Lux::Response)

Current request response object

You can allways use `Lux.current.response` object, or accesss it as `response` inside the controller.

```ruby
# add response header
response.header 'x-blah', 123

# max age of the page in seconds, default 0
response.max_age = 10

# the default access type is private
response.public = true

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

# basic http auth
response.auth do |user, pass|
  [user, pass] == ['foo', 'bar']
end
```





&nbsp;
<a name="secrets"></a>
## Lux.secrets (Lux::Secrets)

Access and protect secrets.

Secrets can be provided in raw yaml file in `./config/secrets.yaml`

#### Protecting secrets file

If you have a secret hash defined in `Lux.config.secret_key_base` or `ENV['SECRET_KEY_BASE']`,
* you can use `bundle exec lux secrets` to compile and secure secrets file (`./config/secrets.yaml`).
* copy of the original file will be placed in `./tmp/secrets.yaml`
* vim editor will be used to edit the secrets file



&nbsp;
<a name="view_cell"></a>
## Lux::ViewCell

View cells are partial view-part/render/controllers combo.

Idea is to have idempotent cell render metod, that can be reused in may places.
You can think of view cells as rails `render_partial` with localized controller attached.

```ruby
class CityCell < ViewCell

  # template_root './apps/cities/cells/views/cities'

  before do
    @skill = parent { @skill }
  end

  ###

  def skills
    @city
      .jobs
      .skills[0,3]
      .map{ |it| it[:name].wrap(:span, class: 'skill' ) }
      .join(' ')
  end

  def render city
    @city    = city
    @country = city.country

    template :city
  end
end
```

And call them in templates like this

```ruby
cell.city.skills
cell.city.render @city
```



&nbsp;
<a name="template"></a>
## Lux::Template

Template rendering engine built on top of Tilt.

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

```ruby
# Set configuration values
Lux.config.key = value

# Get configuration values
Lux.config.key

# Get all config
Lux.config.all

# Check if key exists
Lux.config.key?
```

### Available Configuration Options

```ruby
# Application timeout in seconds
Lux.config.app_timeout = 30

# Delay job timeout
Lux.config.delay_timeout = 30

# Logger configuration
Lux.config.logger_path_mask = './log/%s.log'
Lux.config.logger_files_to_keep = 3
Lux.config.logger_file_max_size = 10_240_000

# Host configuration
Lux.config.host = 'localhost:3000'

# Secret key base for encryption
Lux.config.secret_key_base = ENV['SECRET_KEY_BASE']

# Hooks
Lux.config.on_reload_code { ... }      # Called when code reloads
Lux.config.on_mail_send { |mail| ... } # Called when mail is sent
```

### Environment-Specific Config

```ruby
# Development
Lux.config.no_cache = true       # Disable caching
Lux.config.show_errors = true    # Show detailed errors
Lux.config.screen_log = true      # Log to screen
Lux.config.reload_code = true     # Auto-reload code

# Production
Lux.config.no_cache = false      # Enable caching
Lux.config.show_errors = false   # Hide errors
Lux.config.screen_log = false     # No screen logging
Lux.config.reload_code = false    # No auto-reload
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

#### Dir.all_files

Globs files search into child folders.

All lists are allways sorted with idempotent function response.

Example: get all js and coffee in ./app/assets and remove ./app

`Dir.all_files('./app/assets', ext: [:js, :coffee], root: './app')`

#### Dir.require_all

Requires all found ruby files in a folder, deep search into child folders

`Dir.require_all('./app')`

### Array
#### @array.to_csv

Convert list of lists to CSV

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

Convert float to currency

`@sum.as_currency(pretty: false, symbol: '$')`

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
  lux config          # Show server config
  lux console         # Start console
  lux erb             # Parse and process *.erb templates
  lux evaluate        # Eval ruby string in context of Lux::Application
  lux generate        # Generate models, cells, ...
  lux get             # Get single page by path "lux get /login"
  lux help [COMMAND]  # Describe available commands or one specific command
  lux routes          # Print routes
  lux secrets         # Edit, show and compile secrets
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

The MIT License (MIT) - Copyright (c) 2017 Dino Reić

See LICENSE file for full details.

## Links

* GitHub: http://github.com/dux/lux-fw
* Author: Dino Reić (@dux) - rejotl@gmail.com
