## Lux::Application

* can capture errors with rescue_from
* calls main instance method
* expects @root to have path root and pe string or nil
* expects @path to be array of path attributes

usual workwlow is to parse url, define @root and @path variables

### Instance methods

#### plug

syntatic shugar

```plug :test```

will just call

```test_plug```

#### root

executes if @root is nil

#### mount

mounts specific @root to Cell and calls if root mathes

for example if path is /blogs

```mount :blogs => Main::BlogCell```

will call instance method call with @path expanded

```Main::BlogCell.new.call(*@path)```


#### match

match will call single method and offers viarety of styles

* ```match :blog => BlogCell``` will call ``` BlogCell.action(:blog)```
* ```match :blog => 'blog#single'``` will call ```BlogCell.action(:single)```
* ```match :blog => -> { BlogCell.custom(:whatever) }

### Router example from leanbookmarks.com

```
Lux::Application.class_eval do

  def api_router
    error :forbiden, 'Only POST requests are allowed' if Lux.prod? && @request_method != 'POST'
    Lux::Api.call(@path)
  end

  ###

  def main
    return if plug :lux_static_files
    return if plug :lux_assets

    plug :variables    # load @root and @path
    plug :application  # define app rules
    plug :untaint      # force id an _id to id

    root Lux.current.var.user ? Main::RootCell : GuestCell

    match [:search, :archive]   => Main::RootCell
    match [:stress_me]          => GuestCell
    match [:signup, :login, :profile, :bye, :demo_login] => SessionCell

    match :add    => Main::LinksCell
    mount :n      => Main::NotesCell
    mount :l      => Main::LinksCell
    mount :b      => Main::BucketsCell
    mount :d      => Main::DomainsCell
    mount :labels => Main::LabelsCell

    mount :t      => DomainThumb
    mount :dev    => DevCell
    mount :admin  => AdminCell

    mount :api    => :api_router

    error :not_found unless body?
  end

end
```

### Plugs example

```
Lux::Application.class_eval do

  # force base domain
  def remove_www
    if request.host.split('.').length > 2
      fixed = request.url.sub(/\/\/\w+\./,'//')
      response.redirect fixed, info:"we are forceing no www prefix rule"
    end
  end

  def application_plug
    # redirect in develoment
    # return Lux.current.redirect "http://lvh.me:#{Lux.current.request.port}" if @domain == 'localhost'

    # load user before the api
    SessionCell.load_user_from_session

    @root = @path.shift
    @root = @root.to_sym if @root.kind_of?(String)
    @root.freeze

    error :forbiden, 'Only GET requests are allowed' if @root != :api && !['GET', 'HEAD'].index(@request_method)

    remove_www
  end

  def untaint_plug
    Lux.params[:label] = Lux.params[:label].gsub(/[^\w]/,'') if Lux.params[:label]
    Lux.params[:id] = Lux.params[:id].to_i if Lux.params[:id]

    for k,v in Lux.params
      Lux.params[k] = v.to_i if k == 'id' || k =~ /_id$/
      for k2, v2 in v
        Lux.params[k][k2] = v2.to_i if k2 == 'id' || k2 =~ /_id$/
      end if v.is_hash?
    end
  end

end
```

### Router rescues example

```
Lux::Application.class_eval do

  rescue_from(UnauthorizedError) do |msg|
    if Lux.current.var.user
      raise ErrorCell.unauthorized(msg)
    else
      redirect '/login', error:'No session, please login'
    end
  end

  rescue_from(NotFoundError) do |msg|
    response.status(404)
    if msg == 'Static file not found'
      response.body(msg)
    else
      ErrorCell.not_found(msg || 'Resource not found')
    end
  end

  rescue_from(PG::ConnectionBad) do |msg|
    response.status(500)
    response.body = msg || 'DB connection error, please refresh current.'
  end

end
```