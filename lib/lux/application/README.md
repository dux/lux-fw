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

executes if @root is nil

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

### Router example from leanbookmarks.com

```
Lux.app do

  def api_router
    error :forbiden, 'Only POST requests are allowed' if Lux.prod? && @request_method != 'POST'
    Lux::Api.call nav.path
  end

  ###

  routes do
    plug :lux_static_files
    plug :lux_assets
    plug :variables
    plug :application  # define app rules
    plug :untaint      # force id an _id to id

    root User.current ? Main::RootController : GuestController

    map Main::RootController do
      map :search
      map :archive
      map :alexa
    end

    map GuestController do
      map :p
      map :a
    end

    map SessionController do
      map :signup
      map :login
      map :profile
      map :bye
      map :demo_login
    end

    map api:      :api_router
    map n:        Main::NotesController
    map l:        Main::LinksController
    map d:        Main::DomainsController
    map labels:   Main::LabelsController
    map admin:    AdminController
    map callback: OauthController

    action add:  Main::LinksController

    raise NotFoundError unless body?
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
      when BadRequestError
        current.response.status BadRequestError
        Lux.error "Bad request: #{e.message}"

      when ForbidenError
        ErrorController.forbiden(e.message)

      when UnauthorizedError
        current.response.status UnauthorizedError

        if User.current
          ErrorController.unauthorized(e.message)
        else
          current.redirect '/login', error:'No session, please login'
        end

      when NotFoundError
        ErrorController.not_found(e.message)

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