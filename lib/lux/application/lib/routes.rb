module Lux
  class Application
    module Routes
      # Cached controller class lookups: 'main/users' => Main::UsersController.
      # The reloader re-`load`s files in place, so cached classes stay valid.
      CONTROLLER_CLASS_CACHE ||= {}

      # Cached plugin routes.rb sources: '/abs/path/routes.rb' => source string.
      # Route files are instance_eval'd per request; re-reading them from disk
      # every time is pure overhead outside reload mode.
      PLUGIN_ROUTE_SOURCE ||= {}

      # verb predicates: get?, post?, ...
      # post? { map 'api', 'api#call' }   # block runs on POST only
      # post? 'api', 'api#call'           # same as map, POST only
      # post?                             # bare predicate
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

      # Matches given subdomain name. instance_exec for the same reason as
      # `get?` - the block is captured at class-eval time.
      def subdomain name, &block
        return unless lux.nav.subdomain == name.to_s
        instance_exec(&block)
        raise Lux.error.not_found Lux.debug?('404 Not Found') { 'Subdomain "%s" matched but nothing called' % name }
      end

      # Main routing DSL - one shape: what to match, then what to dispatch.
      #
      # ```
      # map 'users', 'users'            # /users...  -> UsersController, resourceful action
      # map 'users', 'users#index'      # explicit action
      # map 'api', ApplicationApi       # a controller, Lux::Api or Rack class
      # map '/skills/:skill', 'skills#show'   # absolute path, :skill lands in params
      # map %w[help faq], 'pages'       # any of these segments
      # map 'admin' do ... end          # scope: nested routes see the rest of the path
      # ```
      #
      # Unconditional dispatch (no match) is `call`, never `map`.
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
      # Resourceful examples (after `nav.map_path { ... }` canonicalization):
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
      def map path = nil, target = nil, opts = nil, &block
        return if lux.response.body?

        unless path.is_a?(String) || path.is_a?(Array)
          raise ArgumentError, "map takes a path segment, '/abs/:path' or a list of segments first, got #{path.inspect}. Write map 'users', 'users#index'"
        end

        if block
          lux.route.with_scope(1) { instance_exec(lux.route.root, &block) } if route_match?(path)
          return
        end

        unless target
          raise ArgumentError, "map #{path.inspect} needs a target: map 'users', 'users#index'. Use call 'ctrl#action' to dispatch without matching"
        end

        if path.is_a?(String) && path.start_with?('/')
          match_path path, target, opts
        else
          Array(path).each do |segment|
            lux.route.with_scope(1) { call target, nil, opts } if route_match?(segment)
          end
        end
      end

      # Calls target controller and dispatches action.
      #
      # Unconditional dispatch - does not check route_match. Use this inside
      # `rescue_from` blocks or other side-channels where the caller already
      # decided what to run.
      #
      # ```
      # call 'main/orgs'       # resourceful (index/show/edit/...)
      # call 'main/orgs#show'  # explicit :show
      # call Main::UsersController       # a controller, Lux::Api or Rack class
      # call { 'text' }                  # block result is the body;
      # call { [400, {}, ['error']] }    # a [status, headers, body] triple sets status
      # ```
      def call object=nil, action=nil, opts=nil, &block
        # log original app caller (skipped in production - caller() is expensive)
        if Lux.debug?
          root    = Lux.root.join('app/').to_s
          sources = caller.select { |it| it.include?(root) }.map { |it| 'app/' + it.sub(root, '').split(':in').first }
          Lux.log { ' Routed from: %s' % sources.join(' ') } if sources.first
        end

        # Controller#action owns action-name sanitising (every dispatch passes
        # through it), so just normalise the type here.
        action    = action.to_sym if action.is_a?(String)
        object  ||= block if block_given?

        case object
        when String
          if object.include?('#') && !object.end_with?('#')
            # explicit 'controller#action'
            object, action_str = object.split('#', 2)
            action = action_str.to_sym
          else
            # resourceful: 'controller' or 'controller#'
            object = object.chomp('#')
          end
        when Proc
          case data = object.call
          when Array
            lux.response.status = data.first
            lux.response.body data[2].is_a?(Array) ? data[2][0] : data[2]
          else
            lux.response.body data
          end
        when Module
        else
          raise ArgumentError, "call takes 'ctrl#action', a controller/Rack class or a block, got #{object.inspect}"
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
          raise Lux.error.not_found Lux.debug?('404 Not Found') { "Action :#{action} not allowed on #{object}, allowed are: #{opts[:only]}" }
        end

        if opts[:except] && opts[:except].include?(action.to_sym)
          raise Lux.error.not_found Lux.debug?('404 Not Found') { "Action :#{action} not allowed on #{object}, forbidden are: #{opts[:except]}" }
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
        raise "Plugin :#{name} not loaded - call Lux.plugin :#{name} first" unless Lux::Plugin.loaded?(name)
        plugin = Lux::Plugin.get(name)
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
        Lux::Plugin.loaded.each do |plugin|
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

      # Absolute-path match for `map '/:city/people', 'people'`. Captures `:var`
      # placeholders into params and advances the route cursor by the segments
      # consumed, so lux.route.consumed reflects the matched prefix (needed for
      # sub-mounts like Lux::Api to derive their own mount_on).
      def match_path base, target, opts = nil
        captures = lux.route.capture(base) or return

        captures.each { |name, value| lux.params[name] = value }

        lux.route.with_scope(lux.route.capture_length(base)) { call target, nil, opts }
      end

      # Read + instance_eval a plugin routes.rb. The source is memoized unless
      # we are in reload mode, where the file is expected to change under us.
      def eval_plugin_routes path
        source =
          if Lux.reload?
            ::File.read(path)
          else
            PLUGIN_ROUTE_SOURCE[path] ||= ::File.read(path)
          end

        instance_eval source, path, 1
      end

      # Resourceful action resolution from the remaining route cursor path.
      # The action is the last segment that is not a classified id, so it
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

        (remaining.reverse.find { |s| !s.is_a?(Nav::Base) } || :show).to_sym
      end
    end
  end
end
