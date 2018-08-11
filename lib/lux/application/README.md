## Lux::Application

* can capture errors with `on_error`
* calls `before`, `routes` and `after` filters

### Instance methods

#### plug

syntatic shugar

`plug :test`

will just call

`test_plug`

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

### action

Action calls specific action inside call.

```
  action add:  Main::LinksController
```

### Router example

For Lux routing you need to know only few things

* taget can be 5 object variants, look at root example
* "root" method calls object if nav.root is blank?
* "map" method calls object if nav.first == match
* "namespace" method accepts block that wraps

```
Lux.app do

  def api_router
    error :forbiden, 'Only POST requests are allowed' if Lux.prod? && !post?
    Lux::Api.call nav.path
  end

  before do
    plug :lux_static_files
    plug :lux_assets
    plug :custom
  end

  ###

  routes do
    # we show on root method, that target can be multiple object types, 5 variants
    root [RootController, :index] # calls RootController#index
    root RootController           # calls RootController#call
    root :root                    # calls "root" method in current scope
    root 'root'                   # calls RootController#call
    root 'root#index'             # calls RootController#index

    # we can route based on the user status
    root User.current ? Main::RootController : GuestController

    # map "/api" to "api_router" method
    map api: :api_router

    # with MainController
    map MainController do
      map :search      # map "/search" to MainController#search
      map '/login'     # map "/login" to MainController#login
    end

    # map "/foo/dux/baz" route to MainController#foo with params[:bar] == 'dux'
    map '/foo/:bar/baz'  => 'main#foo'

    # if method "foo" in current scope returns true
    namespace :foo do
      # call MainController#foo if request.method == 'GET'
      map 'main#foo' if get?
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

```
Lux.app do
  def error *args
    ErrorController.call *args
  end

  on_error do |e|
    case e
      when Lux::Error
        if error.code == 401
          current.response.status error.code

          if User.current
            # if user has session, then he is forbiden to see the resource
            error 403
          else
            current.redirect '/login', error:'No session, please login'
          end
        end

      when PG::ConnectionBad
        Lux.error "PG: #{e.message}" || 'DB connection error, please refresh current.'

      else
        raise e if Lux.dev?

        key = SimpleException.log(e)
        message = "#{e.class}: #{e.message} \n\nkey: #{key}"
        Lux.error message
    end
  end

  after do
    error(404) unless body?
  end
end
```