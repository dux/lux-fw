module Lux
  class Application
    module Routes
      # Cached controller class lookups: 'main/users' => Main::UsersController
      # Cleared by Lux::Reloader so a reloaded controller class is picked up.
      CONTROLLER_CLASS_CACHE ||= {}

      # Cached plugin routes.rb sources: '/abs/path/routes.rb' => source string.
      # Route files are instance_eval'd per request; re-reading them from disk
      # every time is pure overhead outside reload mode.
      PLUGIN_ROUTE_SOURCE ||= {}

      # generate get, get?, post, post? ...
      # get {}
      # get foo: 'main/bar', only: [:show], except: [:index]
      %w{get head post delete put patch}.each do |m|
        define_method('%s?' % m) do |*args, &block|
          cm = lux.request.request_method
          cm = 'GET' if cm == 'HEAD'
          return unless cm == m.upcase

          if block
            # get? { ... } - instance_exec so `map`/`call` inside the block
            # dispatch on this Application instance. The block was captured at
            # class-eval time, where self is the class, and calling it directly
            # would re-register routes instead of running them.
            instance_exec(&block)
          elsif args.first
            # post api: 'api#call'
            map *args
          else
            true
          end
        end
      end

      # Matches if there is no further segment in the route cursor.
      # ```
      # root 'main#index'
      # ```
      def root target
        call target unless lux.route.root
      end

      # Pure predicate against the route cursor - same frame of reference as
      # `root` and `map`, so inside `map 'admin' do` it tests the segment
      # after /admin. Use `nav.root?` for the absolute answer.
      # root?(:admin) -> true if the cursor is at /admin/...
      def root? name
        lux.route.match? name
      end

      # Absolute-path match. Captures `:var` placeholders into params.
      # ```
      # match '/:city/people', Main::PeopleController
      # ```
      # Advances the route cursor by the number of segments consumed, so
      # lux.route.consumed reflects the matched prefix (needed for sub-mounts
      # like Lux::Api to derive their own mount_on).
      def match base, target
        captures = lux.route.capture(base) or return

        captures.each { |name, value| lux.params[name] = value }

        lux.route.with_scope(lux.route.capture_length(base)) { call target }
      end

      # Matches given subdomain name. instance_exec for the same reason as
      # `get?` - the block is captured at class-eval time.
      def subdomain name, &block
        return unless lux.nav.subdomain == name.to_s
        instance_exec(&block)
        raise Lux.error.not_found Lux.mode.debug?('404 Not Found') { 'Subdomain "%s" matched but nothing called' % name }
      end

      # Main routing DSL. All forms match against the current route cursor first,
      # then dispatch resourcefully unless an explicit action is given via `#`.
      #
      # Match forms (left side):
      # * String/Symbol      - matches a path segment
      # * Array of those     - matches any
      # * String '/abs/:x'   - absolute path match (delegates to `match`)
      #
      # Dispatch forms (right side):
      # * String 'foo'       - FooController, resourceful action
      # * String 'foo#bar'   - FooController#bar (explicit)
      # * Class              - that controller, resourceful action
      # * Class with action  - [Class, :action]
      #
      # A single 'controller#action' string with no left side has nothing to
      # match against, so it dispatches unconditionally - identical to `call`:
      # ```
      # map 'foo#bar'   == call 'foo#bar'   # always runs FooController#bar
      # map 'foo', 'foo#bar'                # runs only when cursor root is 'foo'
      # ```
      #
      # Equivalent forms:
      # ```
      # map 'adm' do; map 'admin'; end
      # map 'adm', 'admin'
      # map adm: :admin
      # ```
      #
      # Halting: a dispatch that writes the response body throws `:done`, which
      # is caught once, in Application#resolve_routes. Every route statement
      # after the matched one is therefore skipped outright - there is no
      # "keep walking the block as no-ops" pass.
      #
      # A trailing opts hash is forwarded to `call`: `:only`/`:except` gate the
      # action, any other key is set as an ivar on the controller.
      # ```
      # map 'users', 'admin/users', foo: :bar   # -> @foo = :bar in the controller
      # ```
      #
      # Resourceful examples (after `nav.ref { ... }` canonicalization):
      # ```
      # /admin                       -> :index
      # /admin/edit                  -> :edit
      # /admin/123                   -> :show   (nav.ref = 123)
      # /admin/123/edit              -> :edit   (nav.ref = 123)
      # /admin/users                 -> :users
      # /admin/users/123             -> :show
      # /admin/users/123/edit        -> :edit
      # /admin/users/foo/bar         -> :foo    (trailing segments past action ignored)
      # ```
      def map route_object = nil, target = nil, opts = nil, &block
        return if lux.response.body?

        # Block form: map 'admin' do ... end
        if block_given?
          if route_match?(route_object)
            lux.route.with_scope(1) { instance_exec(lux.route.root, &block) }
          end
          return
        end

        # Single explicit 'controller#action' string has no left side to match,
        # so it is a pure dispatch - identical to `call`. The match forms
        # (`map 'foo', 'foo#bar'`, `map foo: 'foo#bar'`) still gate on the route
        # cursor below. Also covers the `map 'promo#app_error'` rescue_from shorthand.
        if target.nil? && route_object.is_a?(String) && route_object.include?('#') && !route_object.end_with?('#')
          return call(route_object, nil, opts)
        end

        # Normalize into [match_value, target_value]
        match_value, target_value =
          if target
            [route_object, target]
          else
            # NOTE: inside module Lux, bare `Hash` resolves to Lux::Hash, so
            # plain Ruby hashes never match `when Hash`. Use `is_hash?`.
            if route_object.is_hash?
              [route_object.keys.first, route_object.values.first]
            else
              case route_object
              when String
                # 'X' or 'X#Y' - the part before # is both match and controller
                [route_object.split('#').first, route_object]
              when Symbol
                [route_object, route_object.to_s]
              when Array
                # legacy [match, target] tuple
                [route_object[0], route_object[1]]
              else
                raise Lux.error 'Unsupported route type "%s"' % route_object.class
              end
            end
          end

        # Absolute path match: '/skils/:skill' => 'main/skills#show'
        if match_value.is_a?(String) && match_value.start_with?('/')
          return match(match_value, target_value)
        end

        # Array of route names: [:foo, :bar] => 'root'
        if match_value.is_a?(Array)
          match_value.each do |m|
            lux.route.with_scope(1) { call target_value, nil, opts } if route_match?(m)
          end
          return
        end

        # Standard match
        if route_match?(match_value)
          lux.route.with_scope(1) { call target_value, nil, opts }
        end
      end

      # Calls target controller and dispatches action.
      #
      # Unconditional dispatch - does not check route_match. Use this inside
      # `rescue_from` blocks or other side-channels where the caller already
      # decided what to run.
      #
      # ```
      # call :api_router
      # call { 'string' }
      # call proc { [400, {}, 'error: ...'] }
      # call [200, {}, ['ok']]
      # call Main::UsersController
      # call Main::UsersController, :index
      # call [Main::UsersController, :index]
      # call 'main/orgs'      -> resourceful (index/show/edit/...)
      # call 'main/orgs#show' -> explicit :show
      # ```
      def call object=nil, action=nil, opts=nil, &block
        # log original app caller (skipped in production - caller() is expensive)
        if Lux.mode.debug?
          root    = Lux.root.join('app/').to_s
          sources = caller.select { |it| it.include?(root) }.map { |it| 'app/' + it.sub(root, '').split(':in').first }
          Lux.log { ' Routed from: %s' % sources.join(' ') } if sources.first
        end

        # Controller#action owns action-name sanitising (every dispatch passes
        # through it), so just normalise the type here.
        action    = action.to_sym if action.is_a?(String)
        object  ||= block if block_given?

        # NOTE: bare `Hash` inside module Lux is Lux::Hash, so handle plain
        # Ruby hashes via is_hash? before the case statement.
        if object.is_hash?
          object = [object.keys.first, object.values.first]
        end

        case object
        when Symbol
          return send(object)
        when String
          if object.include?('#') && !object.end_with?('#')
            # explicit 'controller#action'
            object, action_str = object.split('#', 2)
            action = action_str.to_sym
          else
            # resourceful: 'controller' or 'controller#'
            object = object.chomp('#')
          end
        when Array
          if object[0].class == Integer && object[1].is_hash?
            # [200, {}, 'ok']
            for key, value in object[1]
              lux.response.header key, value
            end

            lux.response.status object[0]
            lux.response.body object[2].is_a?(Array) ? object[2].first : object[2]
          else
            object, action = object
          end
        when Proc
          case data = object.call
          when Array
            lux.response.status = data.first
            lux.response.body data[2].is_a?(Array) ? data[2][0] : data[2]
          else
            lux.response.body data
          end
        end

        if object.is_a?(String)
          object = CONTROLLER_CLASS_CACHE[object] ||= ('%s_controller' % object).classify.constantize
        end

        # Lux::Api subclass mounted as a rack app. Mount point resolution:
        # * if the route DSL consumed a prefix (e.g. `map '/admin/api', X`), use it
        # * else fall back to the class's declared mount_on (default '/api')
        # mount_at sets SCRIPT_NAME so the API's auto_mount strips the prefix cleanly.
        if defined?(Lux::Api) && object.is_a?(Class) && object < Lux::Api
          consumed = lux.route.consumed
          mount_at = consumed.any? ? ('/' + consumed.join('/')) : object.mount_on
          mount_at = nil if mount_at == '/' || mount_at.to_s.empty?
          lux.response.rack object, mount_at: mount_at
          throw :done if lux.response.body?
          return
        end

        # Any other Rack-callable class/module. Controllers do not define a
        # class-level `call`, so they never take this branch.
        if [Module, Class].include?(object.class) && object.respond_to?(:call)
          lux.response.rack object
          throw :done if lux.response.body?
          return
        end

        # source_location is [file, line]; files_in_use only keeps strings, so
        # join it into the file:line form the trail already uses
        if location = (object.source_location if object.respond_to?(:source_location))
          lux.files_in_use location.is_a?(Array) ? location.join(':') : location
        end

        opts   ||= {}
        resourceful = action.nil?                       # URL-derived action, not explicit controller#action
        action ||= resourceful_action(lux.route.path)

        if opts[:only] && !opts[:only].include?(action.to_sym)
          raise Lux.error.not_found Lux.mode.debug?('404 Not Found') { "Action :#{action} not allowed on #{object}, allowed are: #{opts[:only]}" }
        end

        if opts[:except] && opts[:except].include?(action.to_sym)
          raise Lux.error.not_found Lux.mode.debug?('404 Not Found') { "Action :#{action} not allowed on #{object}, forbidden are: #{opts[:except]}" }
        end

        if object.respond_to?(:action)
          # Record the controller class so render_error can dispatch the :error
          # action to the right place if something raises mid-action.
          lux.var[:active_controller] = object if object.is_a?(Class)

          # All instance variables set on the Application instance (e.g. in before
          # filters or route blocks) are copied into the controller instance. This
          # allows routes to share data with controllers without explicit passing.
          #
          # Route opts beyond :only/:except are merged in as ivars on top, so
          # `map 'users', 'admin/users', foo: :bar` sets @foo = :bar.
          ivars = instance_variables_hash
          opts.each { |k, v| ivars["@#{k}"] = v unless [:only, :except].include?(k) }
          object.action action.to_sym, ivars: ivars, resourceful: resourceful
        end

        throw :done if lux.response.body?
      end

      # Evaluates `plugins/<name>/routes.rb` in the Application instance, so the
      # plugin's file can use the full routing DSL (map, call, root, ...).
      # The plugin must have been loaded via `Lux.plugin :<name>` beforehand;
      # `plugin_route` does not auto-load to keep ordering explicit.
      #
      # Usage in app routes:
      #   plugin_route :web_common
      #   map 'admin' do
      #     plugin_route :my_plugin   # mount under /admin
      #   end
      def plugin_route name
        plugin = Lux::Plugin::PLUGIN[name.to_s] or raise "Plugin :#{name} not loaded - call Lux.plugin :#{name} first"
        path   = ::File.join(plugin.folder, 'routes.rb')

        raise "Plugin :#{name} has no routes.rb at #{path}" unless ::File.exist?(path)

        eval_plugin_routes path
      end

      # Evaluates `routes.rb` for every loaded plugin that ships one. Plugins
      # without `routes.rb` are silently skipped. Each file is responsible for
      # declaring its own mount path; convention is `/admin/plugins/<name>`.
      #
      # Usage in app routes:
      #   plugin_routes
      def plugin_routes
        Lux::Plugin::PLUGIN.each_value do |plugin|
          path = ::File.join(plugin.folder, 'routes.rb')
          next unless ::File.exist?(path)
          eval_plugin_routes path
        end
      end

      # Pure predicate: checks if the current route cursor's root matches
      # (no side effects). See Lux::Application::Route#match?
      def route_match? route
        lux.route.match? route
      end

      private

      # Read + instance_eval a plugin routes.rb. The source is memoized unless
      # we are in reload mode, where the file is expected to change under us.
      def eval_plugin_routes path
        source =
          if Lux.mode.reload?
            ::File.read(path)
          else
            PLUGIN_ROUTE_SOURCE[path] ||= ::File.read(path)
          end

        instance_eval source, path, 1
      end

      # Resourceful action resolution from the remaining route cursor path.
      # The action is the last segment that is not a `:ref` placeholder, so it
      # reads straight off the tail of the URL:
      #
      #   /users               -> :root
      #   /users/edit          -> :edit
      #   /users/123           -> :show   (nav.ref == '123')
      #   /users/123/edit      -> :edit   (nav.ref == '123')
      #   /users/posts/123     -> :posts
      #   /users/foo/bar       -> :bar
      #
      # Actions that need the id read `nav.ref`; there is no separate `_ref`
      # action name.
      def resourceful_action remaining
        return :root if remaining.empty?

        (remaining.reverse.find { |s| s != :ref } || :show).to_sym
      end
    end
  end
end
