module Lux
  class Application
    module Routes
      # generate get, get?, post, post? ...
      # get {}
      # get foo: 'main/bar', only: [:show], except: [:index]
      %w{get head post delete put patch}.each do |m|
        define_method('%s?' % m) do |*args, &block|
          cm = current.request.request_method
          cm = 'GET' if cm == 'HEAD'
          return unless cm == m.upcase

          if block
            # get? { ... }
            block.call
          elsif args.first
            # post api: 'api#call'
            map *args
          else
            true
          end
        end
      end

      # Matches if there is not root in nav
      # Example calls MainController.action(:index) if in root
      # ```
      # root 'main#index'
      # ```
      def root target
        call target unless nav.root
      end

      # standard route match
      # match '/:city/people', Main::PeopleController
      def match base, target
        base = base.split('/').slice(1, 100)

        base.each_with_index do |el, i|
          if el[0,1] == ':'
            params[el.sub(':','').to_sym] = nav.path[i]
          else
            return unless el == nav.path[i]
          end
        end

        call target
      end

      # Matches given subdomain name
      def subdomain name
        return unless nav.subdomain == name.to_s
        yield
        error.not_found 'Subdomain "%s" matched but nothing called' % name
      end

      # Main routing object, maps path part to target
      # if path part is positively matched with `test?` method, target is called with `call` method
      # ```
      # map api: ApiController
      # map api: 'api'
      # map [:api, ApiController]
      # map 'main/root' do
      # map [:login, :signup] => 'main/root'
      # map :city do
      # map 'city' do
      #   map :about
      # end
      # ```
      def map route_object = nil, &block
        return @magic unless route_object
        return if response.body?

        if block_given?
          # map 'admin' do ...
          if test?(route_object)
            yield
            unless response.body?
              error.not_found("Namespace <b>:#{route_object}</b> matched but nothing is called")
            end
          end

          return
        end

        klass  = nil
        route  = nil
        action = nil
        opts   = {}

        case route_object
        when String
          # map 'root#call'
          call route_object
        when Hash
          route  = route_object.keys.first
          klass  = route_object.values.first

          if route_object.keys.length > 1
            opts = route_object.dup
            opts.delete route
          end

          if route.class == Array
            # map [:foo, :bar] => 'root'
            for route_action in route
              if test?(route_action)
                call klass, route_action
              end
            end

            return
          elsif route.is_a?(String) && route[0,1] == '/'
            # map '/skils/:skill' => 'main/skills#show'
            return match route, klass
          end
        when Array
          # map [:foo, 'main/root']
          route, klass, opts = *route_object
        else
          Lux.error 'Unsupported route type "%s"' % route_object.class
        end

        test?(route) ? call(klass, nil, opts) : nil
      end

      # test if controller or controller + action exist
      # map? 'dashboard/posts'
      # map? 'dashboard/posts#index'
      def map? target
        base, action = target.split('#', 2)
        klass = ('%s_controller' % base).classify

        if Object.const_defined?(klass)
          action ? klass.constantize.respond_to?(action) : true
        else
          false
        end
      end

      # Calls target action in a controller, if no action is given, defaults to :call
      # ```
      # call :api_router
      # call { 'string' }
      # call proc { [400, {}, 'error: ...'] }
      # call [200, {}, ['ok']]
      # call Main::UsersController
      # call Main::UsersController, :index
      # call [Main::UsersController, :index]
      # call 'main/orgs'      -> index, show
      # call 'main/orgs#show' -> show
      # call 'main/orgs?list' -> list_index, list_show # provies namespace in controller
      # ```
      def call object=nil, action=nil, opts=nil, &block
        # log original app caller
        root      = Lux.root.join('app/').to_s
        sources   = caller.select { |it| it.include?(root) }.map { |it| 'app/' + it.sub(root, '').split(':in').first }
        action    = action.gsub('-', '_').to_sym if action && action.is_a?(String)
        namespace = nil
        object  ||= block if block_given?

        Lux.log { ' Routed from: %s' % sources.join(' ') } if sources.first

        case object
        when Symbol
          return send(object)
        when Hash
          object = [object.keys.first, object.values.first]
        when String
          if object.include?('#')
            object, action = object.split('#')
          elsif object.include?('?')
            object, namespace = object.split('?')
          end
        when Array
          if object[0].class == Integer && object[1].class == Hash
            # [200, {}, 'ok']
            for key, value in object[1]
              response.header key, value
            end

            response.status object[0]
            response.body object[2].is_a?(Array) ? object[2].first : object[2]
          else
            object, action = object
          end
        when Proc
          case data = object.call
          when Array
            response.status = data.first
            response.body data[2].is_a?(Array) ? data[2][0] : data[2]
          else
            response.body data
          end
        end

        if object.is_a?(String)
          object = ('%s_controller' % object).classify.constantize
        end

        if [Module, Class].include?(object.class) && object.respond_to?(:call)
          response.rack object
        end

        if object.respond_to?(:source_location)
          current.files_in_use object.source_location
        end

        opts   ||= {}
        action ||= resolve_action object

        # map.pages 'domain?pages'
        # '/pages/1/foo' -> domain#pages_foo
        if namespace
          action = [namespace, action].join('_')
          resolve_action object
        end

        if opts[:only] && !opts[:only].include?(action.to_sym)
          error.not_found Lux.env.dev? ? "Action :#{action} not allowed on #{object}, allowed are: #{opts[:only]}" : nil
        end

        if opts[:except] && opts[:except].include?(action.to_sym)
          error.not_found Lux.env.dev? ? "Action :#{action} not allowed on #{object}, forbidden are: #{opts[:except]}" : nil
        end

        if object.respond_to?(:action)
          object.action action.to_sym
        end
      end

      # Tests current root against the string to get a mach.
      # Used by map function
      def test? route
        root = nav.root.to_s

        ok = case route
        when String
          root == route.sub(/^\//,'')
        when Symbol
          route.to_s == root
        when Regexp
          !!(route =~ root)
        when Array
          !!route.map(&:to_s).include?(root)
        else
          false
        end

        nav.shift if ok

        ok
      end

      private

      # direct template render, bypass controller
      def template name, opts={}
        # rr name
      end

      def action_name name
        name.gsub('-', '_').gsub(/[^\w]/, '')[0, 30].to_sym
      end

      def resolve_action object
        # /
        return :index unless nav.root

        params[:id] = object.path_id(nav.path[0])

        if nav.path[1]
          # /1/foo
          unless params[:id]
            error 'Bad path ID "%s" provided' % nav.path[0]
          end

          action_name nav.path[1]
        else
          if params[:id]
            # /123
            :show
          else
            # /foo
            action_name nav.path[0]
          end
        end
      end

      # internall call to resolve the routes
      def resolve_routes
        @magic = MagicRoutes.new self

        run_callback :before, nav.path
        run_callback :routes, nav.path

        unless response.body?
          error.not_found 'Document not found'
        end

        run_callback :after, nav.path
      end
    end
  end
end


