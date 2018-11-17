## Lux::Application - main application controller and router

* can capture errors with `on_error` instance method
* calls `before`, `routes` and `after` class filters on every request
* routes requests to controllers via `map`, `root` and `call` methods

### Instance methods

#### root

executes if nav.root is empty

#### map

map specific nav root to Controller and calls if root mathes

for example if path is /blogs

`map blogs: Main::BlogController`

will call instance method call with @path expanded

`Main::BlogController.new.call(*@path)`

more examples

* `map blog: BlogController` will call `BlogController.action(:blog)`
* `map blog: 'blog#single'` will call `BlogController.action(:single)`
* `map blog: -> { BlogController.custom(:whatever) }`

### call

Calls specific controller action inside call.

```ruby
  call 'main/links#index'
  call [Main::LinksController, :index]
  call -> { [200, {}, ['OK']]}
```

### Router example

For Lux routing you need to know only few things

* taget can be 5 object variants, look at root example
* "root" method calls object if nav.root is blank?
* "map" method calls object if nav.first == match
* "namespace" method accepts block that wraps map calls.

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

  routes do |r|
    # we show on root method, that target can be multiple object types, 5 variants
    root [RootController, :index] # calls RootController#index
    root 'root#call'              # calls RootController#call
    root :call_root               # calls "call_root" method in current scope
    root 'root'                   # calls RootController#index
    root 'root#foo'               # calls RootController#foo

    # we can route based on the user status
    root User.current ? 'main/root' : 'guest'

    # simple route
    r.about 'static#about'

    # map "/api" to "api_router" method
    r.api :api_router
    # or
    map api: :api_router

    # with MainController
    # map MainController do
    map 'main' do
      map :search      # map "/search" to MainController#search
      map '/login'     # map "/login" to MainController#login
    end

    # map "/foo/dux/baz" route to MainController#foo with params[:bar] == 'dux'
    map '/foo/:bar/baz'  => 'main#foo'

    # if method "city" in current scope returns true
    namespace :city do
      # call MainController#city if request.method == 'GET'
      map 'main#city' if get?
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