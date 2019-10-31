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