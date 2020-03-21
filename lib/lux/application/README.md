## Lux.app (Lux::Application)

Main application controller and router

* can capture errors with `rescue_from` class method
* calls `before`, `routes` and `after` class filters on every request

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

