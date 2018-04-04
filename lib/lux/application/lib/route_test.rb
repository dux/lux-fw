# called by Lux::Application to test route matching
class Lux::Application::RouteTest
  LUX_PRINT_ROUTES = !!ENV['LUX_PRINT_ROUTES'] unless defined?(LUX_PRINT_ROUTES)

  def initialize controller
    @controller = controller
  end

  def current
    Lux.current
  end

  def action route_object, opts={}
    if route_object.class == Hash
      route_test = route_object.keys.first
      route_to   = route_object.values.first
    else
      route_test = route_object
      route_to   = opts[:to] || route_object
    end

    puts '/%s => %s#%s' % [route_test.to_s.ljust(20), @controller.route_target, route_to] if LUX_PRINT_ROUTES

    if test? route_test
      @controller.call @controller.route_target, route_to
    end
  end
  alias :map :action

  def call route
    if test? route
      @controller.call @controller.route_target
    end
  end

  # calls base index if root
  def root
    @controller.call @controller.route_target unless current.nav.root
  end

  def test? route
    case route
      when String
        current.request.path.starts_with?(route)
      when Symbol
        route.to_s == current.nav.root
      when Regexp
        !!(route =~ current.nav.root)
      when Array
        !!route.map(&:to_s).include?(current.nav.root)
      else
        raise 'Route type %s is not supported' % route.class
    end
  end

  def print_route route, action=nil
    return unless LUX_PRINT_ROUTES

    target = @controller.route_target.to_s
    target += '#%s' % action if action

    puts '/%s => %s' % [route.to_s.ljust(20), target]
  end
end