<img alt="Lux logo" width="100" height="100" src="https://i.imgur.com/Zy7DLXU.png" align="right" />

# LUX - ruby web framework

* rack based
* how? # explicit, avoid magic when possible
* why? # fun, learn
* dream? # sinatra speed and memory usage with Rails interface

created by @dux in 2017

## How to start

First, make sure you have `ruby 2.x+` installed.

`gem install lux-fw`

Create new template for lux app

`lux new my-app`

Start the app

`budle exec lux s`

Look at the generated code and play with it.


## Lux module

Main `Lux` module has a few usefull methods.

```ruby
Lux.root     # Pathname to application root
Lux.fw_root  # Pathname to lux gem root
Lux.speed {} # execute block and return speed in ms
Lux.info     # show console info in magenta
Lux.run      # run a command on a server and log it
Lux.die      # stop execution of a program and log
```


## Components

Automaticly loaded



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
* [Lux.template (Lux::Template)](#template) &sdot; [&rarr;](./lib/lux/template)
* [Lux::ViewCell](#view_cell) &sdot; [&rarr;](./lib/lux/view_cell)


### Plugins
You manualy load this

* [Lux.plugin :api](./plugins/api)
* [Lux.plugin :assets](./plugins/assets)
* [Lux.plugin :db](./plugins/db)
* [Lux.plugin :event](./plugins/event)
* [Lux.plugin :favicon](./plugins/favicon)
* [Lux.plugin :html](./plugins/html)
* [Lux.plugin :html_debug](./plugins/html_debug)
* [Lux.plugin :log_exceptions](./plugins/log_exceptions)
* [Lux.plugin :oauth](./plugins/oauth)



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

There are a few route filtes
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
* `map"`method accepts block that wraps map calls.
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
Lux.config.on_code_reload do
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

# deelte
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
after_action do ...  # after action
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

Lux provides only 4 environent modes that are set via `ENV['RACK_ENV']` settings -
  `development`, `production`, `test` and `log`.
  * `test` and `log` are special modes
    * `test`: will retun true to `Lux.env.test?` and `Lux.env.develoment?`
    * `log`: Production mode with output logging. It will retun true for
      `Lux.env.log?` and `Lux.env.production?` or `Lux.env.prod?`.
      This mode is activated if you run server with `bundle exec lux ss`




&nbsp;
<a name="error"></a>
## Lux.error (Lux::Error)

Error handling module.

```ruby
# try to execute part of the code, log exeception if fails
Lux.error.try(name, &block)

# HTML render style for default Lux error
Lux.error.render(desc)

# show error page
Lux.error.show(desc)

# show inline error
Lux.error.inline(name=nil, error_object=nil)

# log exeption via Lux.config.log_exception_via method
Lux.error.log(error_object)
```


#### defines standard Lux errors and error generating helpers

```ruby
# 400: for bad parameter request or similar
Lux.error.forbidden foo

# 401: for unauthorized access
Lux.error.forbidden foo

# 403: for unalloed access
Lux.error.forbidden foo

# 404: for not found pages
Lux.error.not_found foo

# 503: for too many requests at the same time
Lux.error.forbidden foo
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

# write allways to file and provide env sufix
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

# Log to scren in development, ignore in production
Lux.config.logger_stdout do |what|
  return unless Lux.env.dev?
  out = what.is_a?(Proc) ? what.call : what
  puts out
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

sugessted usage

```ruby
Mailer.deliver(:email_login, 'foo@bar.baz')
Mailer.render(:email_login, 'foo@bar.baz')
```

natively works like

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

Render full pages.

As a first argument to any render method you can provide
full [Rack environment](https://www.rubydoc.info/gems/rack/Rack/Request/Env).

If you provide only local path,
[`Rack::MockRequest`](https://www.rubydoc.info/gems/rack/Rack/MockRequest) will be created.

Two ways of creating render pages are provided.

* full builder `Lux.render(@path, @full_opts)`
* helper builder with request method as method name `Lux.render.post(@path, @params_hash, @rest_of_opts)`

```ruby
# opts options
opts = {
  query_string: {}
  post: {},
  body: String
  request_method: String
  session: {}
  cookies: {}
}

page = Lux.render('/about', opts)
page = Lux.render.post('/api/v1/orgs/list', { page_size: 100 }, rest_of_opts)
page = Lux.render.get('/search', { q: 'london' }, { session: {user_id: 1} })

page.info
# render info CleanHash
# {
#   body:    '{}',
#   time:    '5ms',
#   status:  200,
#   session: { user_id: 123 }
#   headers: { ... }
# }

page.render # get only body
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

Access and protext secrets.

Secrets can be provided in raw yaml file in `./config/secrets.yaml`

#### Protecting secrets file

If you have a secret hash defined in `Lux.config.secret_key_base` or `ENV['SECRET_KEY_BASE']`,
* you can use `bundle exec lux secrets` to compile and secure secrets file (`./config/secrets.yaml`).
* copy of the original file will be placed in `./tmp/secrets.yaml`
* vim editor will be used to edit the secrets file



&nbsp;
<a name="template"></a>
## Lux.template (Lux::Template)

Renders templates, wrapper arround [ruby tilt gem](https://github.com/rtomayko/tilt).

```ruby
Lux.template.render(@scope, @template)
Lux.template.render(@scope, template: @template, layout: @layout_file)
Lux.template.render(@scope, @layout_template) { @yield_data }
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





&nbsp;
<a name="view_cell"></a>
## Lux::ViewCell

View cells a partial view-part/render/controllers combo.

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
## Methods added to base Ruby classes

### Dir
#### Dir.folders

Get list of folders in a folder

`Dir.folders('./app/assets')`

#### Dir.files

Get all files in a folder

`Dir.files('./app/assets')`

#### Dir.all_files

Gobs files search into child folders.

All lists are allways sorted with idempotent function response.

Example: get all js and coffee in ./app/assets and remove ./app

`Dir.all_files('./app/assets', ext: [:js, :coffee], root: './app')`

#### Dir.require_all

Requires all found ruby files in a folder, deep search into child folders

`Dir.require_all('./app')`

### Array
#### @array.to_csv

Aonvert list of lists to CSV

#### @array.last=

Set last element of an array

#### @array.to_sentence

Convert list to sentence, Rails like

`@list.to_sentence(words_connector: ', ', two_words_connector: ' and ', last_word_connector: ', and ')`

#### @array.toggle

Toggle existance of an element in array and return true when one added

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

Convert float to currenct

`@sum.as_currency(pretty: false, symbol: '$')`

## Lux command line helper

You can run command `lux` in your app home folder.

If you have `capistrano` or `mina` installed, you will see linked tasks here as well.

```bash
$ lux
Commands:
  lux config          # Show server config
  lux console         # Start console
  lux erb             # Parse and process *.erb templates
  lux evaluate        # Eval ruby string in context of Lux::Application
  lux generate        # Genrate models, cells, ...
  lux get             # Get single page by path "lux get /login"
  lux help [COMMAND]  # Describe available commands or one specific command
  lux routes          # Print routes
  lux secrets         # Edit, show and compile secrets
  lux server          # Start web server
  lux stats           # Print project stats

Rake tasks:
  rake assets:compile    # Build and generate manifest
  rake assets:install    # Install example rollup.config.js, package.json and Procfile
  rake db:am             # Automigrate schema
  rake db:console        # Run PSQL console
  rake db:create         # Create database
  rake db:drop           # Drop database
  rake db:dump[name]     # Dump database backup
  rake db:reset          # Reset database (drop, create, auto migrate, seed)
  rake db:restore[name]  # Restore database backup
  rake db:seed:gen       # Create seeds from models
  rake db:seed:load      # Load seeds from db/seeds
  rake docker:bash       # Get bash to web server while docker-compose up
  rake docker:build      # Build docker image named stemical
  rake docker:up         # copose up
  rake exceptions        # Show exceptions
  rake exceptions:clear  # Clear all excpetions
  rake images:reupload   # Reupload images to S3
  rake job:process       # Process delayed job que tasks (NSQ, Faktory, ...)
  rake job:start         # Start delayed job que tasks Server (NSQ, Faktory, ...)
  rake nginx:edit        # Edit nginx config
  rake nginx:generate    # Generate sample config
  rake start             # Run local dev server
  rake stat:goaccess     # Goaccess access stat builder
```
