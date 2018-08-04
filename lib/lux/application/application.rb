class Lux::Application
  LUX_PRINT_ROUTES = !!ENV['LUX_PRINT_ROUTES'] unless defined?(LUX_PRINT_ROUTES)

  class_callbacks :before, :after, :routes, :on_error

  attr_reader :route_target, :current

  # define common http methods as constants
  [:get, :head, :post, :delete, :put, :patch].map(&:to_s).map(&:upcase).each { |m| eval "#{m} ||= '#{m}'" }

  # simple one liners and delegates
  define_method(:request)  { @current.request }
  define_method(:params)   { @current.request.params }
  define_method(:nav)      { @current.nav }
  define_method(:redirect) { |where, flash={}| @current.redirect where, flash }
  define_method(:get?)     { request.request_method == GET }
  define_method(:post?)    { request.request_method == POST }
  define_method(:done?)    { throw :done if response.body }

  ###

  def initialize current
    @current = current
  end

  def debug
    { :@locale=>@locale, :@nav=>nav, :@subdomain=>@subdomain, :@domain=>@domain }
  end

  def body?
    response.body ? true : false
  end

  def body data
    response.body data
  end

  def plug name, &block
    done?

    m = "#{name}_plug".to_sym
    return Lux.error(%[Method "#{m}" not defined in #{self.class}]) unless respond_to?(m)
    send m, &block

    done?
  end

  def cell_target? route
    # symbol is method reference
    ! [Symbol].include?(route.class)
  end

  def response body=nil, status=nil
    return @current.response unless body

    response.body body
    response.status status || 200

    throw :done
  end

  # def print_route route
  #   return unless LUX_PRINT_ROUTES

  #   puts '%s => %s' % []
  # end

  def test? route
    root = nav.root.to_s

    case route
      when String
        root == route.sub(/^\//,'')
      when Symbol
        route.to_s == root
      when Regexp
        !!(route =~ root)
      when Array
        !!route.map(&:to_s).include?(root)
      else
        raise 'Route type %s is not supported' % route.class
    end
  end

  def target_has_action? target
    return !!
      target.class == Array ||
      (target.class == String && target.include?('#'))
  end

  # gets only root
  def root cell=nil
    call @cell_object unless cell
    call cell         unless nav.root
  end

  # standard route match
  # match '/:city/people' => Main::PeopleController
  def match opts
    base, target = opts.keys.first.split('/').slice(1, 100), opts.values.first

    base.each_with_index do |el, i|
      if el[0,1] == ':'
        params[el.sub(':','')] = nav.original[i]
      else
        return unless el == nav.original[i]
      end
    end

    call target
  end

  # action about: RootController
  # action about: 'root#about_us'
  def action object
    route, target = object.keys.first, object.values.first
    map(target) { map route }
  end

  @@namespaces ||= {}
  def self.namespace name, &block
    @@namespaces[name] = block
  end

  # namespace 'dashboard' do
  #   map orgs: 'dashboard/orgs'
  # end
  def namespace name
    if String === name
      return unless nav.root == name.to_s
      nav.shift
    else
      if @@namespaces[name]
        return unless instance_exec &@@namespaces[name]
      else
        raise ArgumentError.new('Namespace block :%s is not defined' % name)
      end
    end

    yield

    raise Lux::Error.not_found("Namespace <b>:#{name}</b> matched but nothing is called")
  end

  # map api: ApiController
  # map Main::RootController do
  #   action :about
  #   action '/verified-user'
  # end
  # map :foo do
  #   map Foo::BarController do
  #     map :bar
  #   end
  # end
  def map route_object, opts={}, &block
    done?

    # if given hash
    if route_object.class == Hash
      route  = route_object.keys.first
      target = route_object.values.first

      # return if no match
      return unless test?(route)

      # must resolve
      if cell_target?(target) || target.class == String
        # in maped hash call, drop nav element
        nav.shift unless target_has_action?(target)
        call target
      else
       call [@cell_object, opts[:to] || target]
      end
    end

    # nested map :foo
    unless block_given?
      if @cell_object
        call [@cell_object, route_object] if test? route_object
        return
      else
        raise ArgumentError.new('Block expected but not given for %s' % route_object)
      end
    end

    # map FooController do
    if cell_target?(route_object)
      @cell_object = route_object
      instance_exec &block
    end

    Lux.error ['Symbol as map attribute is not supported, use namespace method', caller[0]].join("\n\n") if route_object.class == Symbol
  end

  # call :api_router
  # call proc { ... }
  # call Main::UsersController
  # call Main::UsersController, :index
  # call 'main/orgs#show'
  def call object=nil, action=nil
    done?

    # log original app caller
    root    = Lux.root.join('app/').to_s
    sources = caller.select { |it| it.include?(root) }.map { |it| 'app/' + it.sub(root, '').split(':in').first }
    Lux.log ' Routed from: %s' % sources.join(' ') if sources.first

    action = nil

    case object
      when Symbol
        return send(object)
      when Hash
        object = [object.keys.first, object.values.first]
      when String
        object, action = object.split('#') if object.include?('#')
      when Array
        object, action = object
    end

    object = ('%s_controller' % object).classify.constantize if object.class == String

    if action
      object.action action
    else
      object.call
    end

    if body?
      done?
    else
      Lux.error 'Lux cell "%s" called via route "%s" but page body is not set' % [object, nav.root]
    end
  end

  def main
    catch(:done) do
      begin
        class_callback :before
        class_callback :routes
        class_callback :after
      rescue => e
        class_callback :on_error, e
      end
    end
  end

  def render
    Lux.log "\n#{current.request.request_method.white} #{current.request.url}"

    Lux::Config.live_require_check! if Lux.config(:auto_code_reload)

    main

    response.render
  end

end