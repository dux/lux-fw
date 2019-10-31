# LUX - ruby web framework

![Lux logo](https://i.imgur.com/Zy7DLXU.png)

* rack based
* explicit, avoid magic when possible

created by @dux in 2017

## How to start

First, make sure you have `ruby 2.x+`, `npm 6.x+` and `yarn 1.x+` installed.

Install Lux framework.

`gem install lux-fw`

Create new template for lux app

`lux new my-app`

Start the app

`lux s`

Look at the generated code and play with it.





## Lux::Application - main application controller and router
* can capture errors with `on_error` instance method
* calls `before`, `routes` and `after` class filters on every request

### Instance methods

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


### Class filters

There are a few route filtes
* `config`    # pre boot app config
* `boot`      # after rack app boot (web only)
* `info`      # called by "lux config" cli
* `before`    # before any page load
* `routes`    # routes resolve
* `after`     # after any page load
* `on_error`  # on routing error


### Router example

For Lux routing you need to know only few things

* `get?`, `post?`, `delete?`, ... will be true of false based HTTP_REQUEST type
* "namespace" method accepts block that wraps map calls.
  * `namespace :city do ...` will call `city_namespace` method. it has to return falsey if no match
  * `namespace 'city' do ...` will check if we are under `/city/*` nav namespace

```ruby
Lux.app do

  def api_router
    error :forbiden, 'Only POST requests are allowed' if Lux.prod? && !post?
    Lux::Api.call nav.path
  end

  before do
    check_subdomain
  end

  after do
    error 404
  end

  ###

  routes do |nav_path_array|
    # we show on root method, that target can be multiple object types, 5 variants
    # this target is valid target for any of the follwing methods: get, post, map, call, root
    root [RootController, :index] # calls RootController#index
    root 'root#index'             # calls RootController#index
    root 'root'                   # calls RootController#call

    root 'main/root'

    # simple route, only for GET
    map.about 'static#about' if get?

    # execute blok if POST
    post? do
      # map "/api" to "api_router" method
      map.api :api_router
      # or
      map api: :api_router
    end

    # map "/foo/dux/baz" route to MainController#foo with params[:bar] == 'dux'
    map '/foo/:bar/baz'  => 'main#foo'

    # call method "city", if it returns true, proceed
    namespace :city do
      # call MainController#city if request.method == 'GET'
      map 'main#city'
    end

    # if we match '/foo' route
    namespace 'foo' do
      # call MainController#foo with params[:bar] == '...'
      map '/baz/:bar' => 'main#foo'
    end
  end
end
```

### Router rescues example

```ruby
Lux.app do
  def on_error error

    message = case error
      when PG::ConnectionBad
        msg = error.message || 'DB connection error, please refresh page.'
        msg = "PG: #{msg}"
        Lux.logger(:db_error).error msg
        msg

      when Lux::Error
        # for handled errors
        # show HTTP errors in a browser without a log
        Main::RootController.action(:error, error)

      else
        # raise errors in developmet
        raise error if Lux.dev?

        key = Lux.error.log error
        "#{error.class}: #{error.message} \n\nkey: #{key}"
    end

    # use default error formater
    Lux.error message
  end
end

if Lux.prod?
  Lux.config.error_logger = proc do |error|
    # log and show error page in a production
    key = SimpleException.log error
    Lux.cache.fetch('error-mail-%s' % key) { Mailer.error(error, key).deliver }
    Lux.logger(:exceptions).error [key, User.current.try(:email).or('guest'), error.message].join(' - ')
    key
  end
end
```

### Lux::Application methods

#### on_error

Action to do if there is an application error.
You want to overload this in a production.

## Lux::Controller - Simplified Rails like view controllers
Controllers are Lux view models

* all cells shoud inherit from Lux::Controller
* `before`, `before_action` and `after` class methods supportd
* instance_method `on_error` is supported
* calls templates as default action, behaves as Rails controller.

### Example code

```ruby
require 'lux-fw'

class Main::RootController < Lux::Controller
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

  ###

  mock :show # mock `show` action

  def index
    render text: 'Hello world'
  end

  def foo
    # renders ./app/views/main/root/foo.(haml, erb)
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

    # transfer to Main::Foo#bar
    action 'main/foo#bar'
  end

end
```

### Lux::Controller methods

#### action

action(:show)
action(:select', ['users'])

#### mock

create mock function, to enable template rendering
mock :index, :login

#### root

template root sensitve root

#### send_file

send file to browser

#### render

render :index
render 'main/root/index'
render text: 'ok'

#### render_to_string

does not set the body, returns body string

#### render_javascript

shortcut to render javascript

#### render_resolve

called be render

#### respond_to

respond_to :js do ...
respond_to do |format| ...

#### filter

because we can call action multiple times
ensure we execute filters only once

## Lux::View - Backend template helpers
Template based rendering helpers

### Tempalte render flow

* Lux::View.render_with_layout('main/users/show', { :@user=>User.find(1) })
* Lux::View.render_part('main/users/show', { :@user=>User.find(1) })
* helper runtime context is prepared by Lux::View::Helper.for('main')
* templte 'main/users/show' is renderd with options
* layout template 'main/layout' is renderd and previous render result is injected via yield


### Lux::View - Calling templates

* all templates are in app/views folder
* you can call template with Lux::View.render_with_layout(template, opts={}) or Lux::View.render_part(template, opts={})
* Lux::View.render_with_layput renders template with layout
* Lux::View.render_part renders without layout


### Inline render

```ruby
= render :_part, name: 'Foo'
```

in `_part.haml` access option `name: ...` via instance variable `@_name`


### Lux::View::Helper

Lux Helpers provide easy way to group common functions.

* helpers shud be in app/helpers folder
* same as Rails View helpers
* called by Lux::View before rendering any view


### Example

for this to work

```Lux::View::Helper.for(:rails, @instance_variables_hash).link_to(...)```

RailsHelper module has to define link_to method

### ViewCell

View components in rails

Define them like this

```ruby
class CityCell < ViewCell

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

And call them on templates like this

```ruby
cell.city.skills
cell.city.render @city
```

## Lux::Current - Main state object
Current application state as single object. Defined in Thread.current, available everywhere.

`Lux.current` - current response state

* `session`         - session, encoded in cookie
* `locale`          - locale, default nil
* `request`         - Rack request
* `response`        - Lux response object
* `nav`             - lux nav object
* `cookies`         - Rack cookies
* `can_clear_cache` - set to true if user can force refresh cache



### Lux::Current methods

#### host

Full host with port

#### var

Current scope variables hash

#### cache

Cache data in current request

#### no_cache?

Set Lux.current.can_clear_cache = true in production for admins

#### once

Execute action once per page

#### uid

Generete unique ID par page render

#### secure_token

Get or check current session secure token

#### files_in_use

Add to list of files in use

## Lux::Mailer - send mails
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

### Example

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

### Example code

```ruby
class Mailer < Lux::Mailer
  helper :mailer

  # before mail is sent
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

    @link    = "#{App.http_host}/profile/password?user_hash=#{Crypt.encrypt(email)}"
  end
end
```

### Lux::Mailer methods

#### prepare

Mailer.prepare(:email_login, 'foo@bar.baz')

# Lux::Config - Config loader helpers
Methods for config and pluin loading.

## Lux::Config::Plugins

* loads plugins in selected namespace, default namespace :main
* gets plugins in selected namespace

```ruby
Lux.plugin name_or_folder
Lux.plugin name: :foo, folder: '/.../...', namespace: [:main, :admin]
Lux.plugin name: :bar

Luxp.lugin.folders :admin # => [:foo]
Luxp.lugin.folders # => [:foo, :bar]
```

## Lux::Config::Secrets

Similar to rails 5.1+, we can encode secrets for easy config.

* using JWT HS512
* create and write sectes in YAML format in `./tmp/secrets.yaml`
* run `lux secrets` to compile secretes to `./config/secrets.txt`
* use "shared" hash for shared secrets
* sectets are available in app via `Lux.secrets`, as struct object

### lux secrets

* compiles unencoded sectes from `./tmp/secrets.yaml` to `./config/secrets.txt`
* creates editable file `./tmp/secrets.yaml` from `./config/secrets.txt` if one exists
* shows available secrets for current environment

### Example

Env development

Secrets file `./tmp/secrets.yaml`

```
shared:
  x: s
  b:
    c: nested

production:
  a: p

development:
  a: d
```

`lux secrets` - will compile secrets or create template if needed

`lux c` - console

```ruby
Lux.secrets.a == "d"
Lux.secrets.x == "s"
Lux.secrets.b.c == "nested"
```



### Lux::Config methods

#### require_all

requires all files recrusive in, with spart sort

#### show_config

preview config in development

## Lux::Cache - Mimics Rails.cache interface
Alias - `Lux.cache`

### Define

use RAM cache in development, as default

```
Lux::Cache.server = :memcached
```

You can use memcached or redis in production

```
Lux::Cache.server  = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })
```

### Lux::Cache instance methods

Mimics Rails cache methods

```
  Lux.cache.read(key)
  Lux.cache.get(key)

  Lux.cache.read_multi(*args)
  Lux.cache.get_multi(*args)

  Lux.cache.write(key, data, ttl=nil)
  Lux.cache.set(key, data, ttl=nil)

  Lux.cache.delete(key, data=nil)

  Lux.cache.fetch(key, ttl=nil, &block)

  Lux.cache.is_available?
```

Has method to generate cache key

```
  # generates unique cache key based on set of data
  # Lux.cache.generate_key([User, Product.find(3), 'data', @product.updated_at])

  Lux.cache.generate_key(*data)
```

### Lux::Cache methods

#### server=

sert cache server
Lux.cache.server = :memory
Lux.cache.server = :memcached
Lux.cache.server = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })

## Lux::Errors - In case of error
### module Lux::Error

```ruby
  # try to execute part of the code, log exeception if fails
  def try(name, &block)

  # HTML render style for default Lux error
  def render(desc)

  # show error page
  def show(desc)

  # show inline error
  def inline(name=nil, o=nil)

  # log exeption
  def log(exp_object)
```


### defines standard Lux errors and erro generating helpers

```ruby
# 400: for bad parameter request or similar
Lux::Error.forbidden foo

# 401: for unauthorized access
Lux::Error.forbidden foo

# 403: for unalloed access
Lux::Error.forbidden foo

# 404: for not found pages
Lux::Error.not_found foo

# 503: for too many requests at the same time
Lux::Error.forbidden foo

```


### Lux::Error methods

#### render

template to show full error page

#### inline

render error inline or break in production

## Lux::Response

### Lux::Response methods

#### early_hints

http 103

#### redirect_to

redirect_to '/foo'
redirect_to :back, info: 'bar ...'

#### auth

auth { |user, pass| [user, pass] == ['foo', 'bar'] }