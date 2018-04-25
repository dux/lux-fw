class Lux::Application
  class_callbacks :before, :after, :routes, :on_error

  attr_reader :route_target, :current

  # define common http methods as constants
  [:get, :head, :post, :delete, :put, :patch].map(&:to_s).map(&:upcase).each { |m| eval "#{m} ||= '#{m}'" }

  # simple one liners and delegates
  define_method(:request)  { @current.request }
  define_method(:response) { @current.response }
  define_method(:params)   { @current.params }
  define_method(:nav)      { @current.nav }
  define_method(:redirect) { |where, flash={}| @current.redirect where, flash }
  define_method(:get?)     { request.request_method == GET }
  define_method(:post?)    { request.request_method == POST }
  define_method(:done?)    { throw :done if response.body }

  ###

  def initialize current
    @current = current
    @route_test = Lux::Application::RouteTest.new self
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

  # gets only root
  def root cell
    if RouteTest::LUX_PRINT_ROUTES
      @route_target = cell
      @route_test.print_route ''
    end

    call cell unless nav.root
  end

  def plug name, &block
    done?

    m = "#{name}_plug".to_sym
    return Lux.error(%[Method "#{m}" not defined in #{self.class}]) unless respond_to?(m)
    send m, &block

    done?
  end

  # standard route match
  # match '/:city/people' => Main::PeopleCell
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

  # map Main::RootCell do
  #   action :about
  #   action '/verified-user'
  # end
  # map api: ApiCell
  def map route_object, &block
    done?

    if route_object.class == Hash
      @route_name   = route_object.keys.first
      @route_target = route_object.values.first
    else
      @route_name   = nav.root
      @route_target = route_object

      if block_given?
        # map :dashboard do
        #   map o: DashboardOrgsCell
        #   root DashboardCell
        # end
        if route_object.class == Symbol
          if test?(route_object)
            current.nav.shift_to_root
            instance_exec &block
            raise NotFoundError.new %[Route "#{route_object}" matched but nothing is called]
          end

          return
        end
      else
        @route_test.print_route '*'
        return route_object.call
      end
    end

    if block_given?
      @route_test.instance_exec &block
      return
    end

    @route_test.print_route '%s/*' % @route_name

    call @route_target if test? @route_name
  end

  # action about: RootCell
  # action about: 'root#about_us'
  def action route_object
    map route_object.values.first do
      action route_object.keys.first
    end
  end

  def test? route
    @route_test.test? route
  end

  # call :api_router
  # call proc { ... }
  # call Main::UsersCell
  # call Main::UsersCell, :index
  # call 'main/orgs#show'
  def call object=nil, action=nil
    done?

    case object
      when Symbol
        return send(object)
      when Hash
        object = [object.keys.first, object.values.first]
      when String
        if object.include?('#')
          object = object.split('#')
          object[0] = ('%s_cell' % object[0]).classify.constantize
        else
          object = ('%s_cell' % object).classify.constantize
        end
    end

    object, action = object if object.is_a? Array

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
    Lux.log "\n#{current.request.request_method.white} #{current.request.path.white}"

    Lux::Config.live_require_check! if Lux.config(:auto_code_reload)

    main

    response.render
  end

end