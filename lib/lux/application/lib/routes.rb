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
        Lux.error.not_found 'Subdomain "%s" matched but nothing called' % name
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
      def map route_object = nil, target = nil, &block
        return if response.body?

        route_object = [route_object, target] if target

        if block_given?
          # map 'admin' do ...
          if test?(route_object)
            yield nav.root
            nav.unshift
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
          nav.shift
          catch(:done) { call route_object }
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
          else
            # simple logic
            #   /foo -> 'foo#index'
            #   /foo/:show -> 'foo#show'
            #   /foo/:show/bar -> 'foo#bar'
            action = nav.path[1] || nav.root.or(:index)
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
        action ||= nav.path.last || :index

        if opts[:only] && !opts[:only].include?(action.to_sym)
          Lux.error.not_found Lux.env.show_errors? ? "Action :#{action} not allowed on #{object}, allowed are: #{opts[:only]}" : nil
        end

        if opts[:except] && opts[:except].include?(action.to_sym)
          Lux.error.not_found Lux.env.show_errors? ? "Action :#{action} not allowed on #{object}, forbidden are: #{opts[:except]}" : nil
        end

        if object.respond_to?(:action)
          object.action action.to_sym, ivars: instance_variables_hash
        end

        throw :done if response.body?
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
      end
    end
  end
end


