module Lux
  class Router
    module Routes
      # Cached router class lookups: 'main/users' => Main::UsersRouter.
      # The reloader re-`load`s files in place, so cached classes stay valid.
      ROUTER_CLASS_CACHE ||= {}

      # Compiled plugin routes.rb files: '/abs/path/routes.rb' => [mtime, proc].
      PLUGIN_ROUTE_PROCS ||= {}

      # verb predicates: get?, post?, ...
      # post? { map 'api', ApiRouter }   # block runs on POST only
      # post? 'hook', :hook              # same as map, POST only
      # post?                            # bare predicate
      %w{get head post delete put patch}.each do |m|
        define_method('%s?' % m) do |*args, **opts, &block|
          cm = lux.request.request_method
          cm = 'GET' if cm == 'HEAD'
          return unless cm == m.upcase

          if block
            instance_exec(&block)
          elsif args.first
            map *args, **opts
          else
            true
          end
        end
      end

      # Dispatches only when the route cursor is empty.
      #   root 'main#index'      # == map '', 'main#index'
      def root target, **opts
        map '', target, **opts
      end

      # Pure predicate against the route cursor - same frame of reference as
      # `root` and `map`, so inside `map 'admin' do` it tests the segment
      # after /admin. Use `nav.root?` for the absolute answer.
      # root?(:admin) -> true if the cursor is at /admin/...
      def root? name
        lux.route.match? name
      end

      # Matches given subdomain name. The block must dispatch, else 404.
      def subdomain name, &block
        return unless lux.nav.subdomain == name.to_s
        instance_exec(&block)
        throw :done if lux.response.body?
        raise Lux.error.not_found Lux.debug?('404 Not Found') { 'Subdomain "%s" matched but nothing called' % name }
      end

      # The one routing word: what to match, then what to dispatch.
      #
      # ```
      # map 'admin' do ... end              # scope: nested routes see the rest of the path
      # map :spaces, :ref, :admin do ... end  # segments matched in sequence, :ref by type
      # map 'users', UsersRouter            # mount a router, run its route
      # map 'users', 'users'                # same, by name -> UsersRouter
      # map 'login', 'guest#login'          # mount GuestRouter, run action :login
      # map 'logout', :logout               # action on this router
      # map 'api', ApplicationApi           # Lux::Api or any Rack class
      # map '/skills/:skill', 'skills#show' # absolute path, :skill lands in params
      # map %w[help faq], 'pages'           # any of these segments
      # map 'boards', :ref, 'edit', :edit   # several segments, then the target
      # map MainRouter                      # one arg: dispatch without matching
      # map 'promo#auto'
      # ```
      #
      # Halting: a dispatch that writes the response body throws `:done`, which
      # is caught once, in Router#resolve_routes (or a mounted router's own
      # run). Every route statement after the matched one is skipped outright.
      #
      # Keyword opts go to the target: `:only`/`:except` gate a mounted
      # router's actions, any other key is set as an ivar on it.
      # ```
      # map 'users', 'admin/users', foo: :bar   # -> @foo = :bar in Admin::UsersRouter
      # ```
      #
      # Resourceful actions (a router with no `route` block):
      # ```
      # /admin                       -> :index
      # /admin/edit                  -> :edit
      # /admin/123                   -> :show   (nav.ref = 123)
      # /admin/123/edit              -> :edit   (nav.ref = 123)
      # /admin/users/foo/bar         -> :bar
      # ```
      def map *args, **opts, &block
        throw :done if lux.response.body?

        if block
          raise ArgumentError, 'map with a block takes segments only' if opts.any?
          raise ArgumentError, 'map with a block needs a path segment' if args.empty?

          check_map_segments! args
          matched = map_scope(args, &block)

          # guards fall through on purpose; a block that forgot to render would
          # otherwise end in `auto` or a 404 with nothing pointing back at it
          if matched && Lux.debug?
            file, line = block.source_location
            Lux.log { ' map %s (%s:%d) rendered nothing, routing continues' % [args.map(&:inspect).join(', '), Lux.root.pretty(file), line] }
          end
          return
        end

        if args.empty?
          raise ArgumentError, "map needs a target: map 'users', UsersRouter"
        end

        if args.length == 1
          target = args.first

          if target.is_a?(::String) && !target.include?('#')
            raise ArgumentError, "map #{target.inspect} needs a target: map 'users', UsersRouter. To dispatch without matching write map UsersRouter or map 'users#action'"
          end

          return map_dispatch(target, opts)
        end

        target = args.pop

        if args.length == 1 && args.first.is_a?(::String) && args.first.start_with?('/')
          return match_path(args.first, target, opts)
        end

        check_map_segments! args
        map_scope(args) { map_dispatch target, opts }
      end

      # Evaluates `plugins/<name>/routes.rb` in the Router instance, so the
      # plugin's file can use the full routing DSL (map, root, ...).
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
      # (no side effects). See Lux::Router::Route#match?
      def route_match? route
        lux.route.match? route
      end

      private

      def check_map_segments! segments
        segments.each do |segment|
          next if [::String, ::Symbol, ::Regexp, ::Array].any? { segment.is_a?(_1) }

          raise ArgumentError, "map takes path segments (String, Symbol, Regexp or a list of them) before the target, got #{segment.inspect}. Write map 'users', UsersRouter"
        end
      end

      # Matches the segments one by one against the route cursor, each in its
      # own scope, then runs the block with the next segment. True when the
      # segments matched (the block ran and did not render).
      def map_scope segments, &block
        return false unless lux.route.match?(segments.first)

        lux.route.with_scope(1) do
          if segments.length > 1
            map_scope segments.drop(1), &block
          else
            instance_exec lux.route.root, &block
            true
          end
        end
      end

      # Absolute-path match for `map '/:city/people', 'people'`. Captures `:var`
      # placeholders into params and advances the route cursor by the segments
      # consumed, so lux.route.consumed reflects the matched prefix (needed for
      # sub-mounts like Lux::Api to derive their own mount_on).
      def match_path base, target, opts
        captures = lux.route.capture(base) or return

        captures.each { |name, value| lux.params[name] = value }

        lux.route.with_scope(lux.route.capture_length(base)) { map_dispatch target, opts }
      end

      def map_dispatch target, opts
        throw :done if lux.response.body?

        # log original app caller (skipped in production - caller() is expensive)
        if Lux.debug?
          root    = Lux.root.join('app/').to_s
          sources = caller.select { |it| it.include?(root) }.map { |it| 'app/' + it.sub(root, '').split(':in').first }
          Lux.log { ' Routed from: %s' % sources.join(' ') } if sources.first
        end

        case target
        when ::Symbol
          opts.each { |k, v| instance_variable_set "@#{k}", v }
          action target
        when ::String
          name, action_name = target.split('#', 2)
          map_mount router_class(name), (action_name.to_sym unless action_name.to_s.empty?), opts
        else
          if target.is_a?(::Class) && target < Lux::Router
            map_mount target, nil, opts
          elsif defined?(Lux::Api) && target.is_a?(::Class) && target < Lux::Api
            # Mount point: the prefix the route consumed (`map 'admin/api', X`),
            # else the class's declared mount_on (default '/api'). mount_at sets
            # SCRIPT_NAME so the API's auto_mount strips the prefix cleanly.
            consumed = lux.route.consumed
            mount_at = consumed.any? ? ('/' + consumed.join('/')) : target.mount_on
            mount_at = nil if mount_at == '/' || mount_at.to_s.empty?
            lux.response.rack target, mount_at: mount_at
          elsif target.is_a?(::Module) && target.respond_to?(:call)
            lux.response.rack target
          else
            raise ArgumentError, "map target must be a Router class, 'router#action', 'router', a Symbol action or a Rack app, got #{target.inspect}"
          end
        end

        throw :done if lux.response.body?
      end

      # Runs a router class in a fresh instance that sees this router's ivars
      # (framework state is @_ prefixed and stays behind).
      def map_mount klass, action_name, opts
        router = klass.new
        state  = router.instance_variable_get(:@_lux)

        instance_variables_hash.each { |k, v| router.instance_variable_set k, v }

        opts.each do |k, v|
          if k == :only || k == :except
            state[k] = Array(v).map(&:to_sym)
          else
            router.instance_variable_set "@#{k}", v
          end
        end

        # source_location is [file, line]; files_in_use only keeps strings, so
        # join it into the file:line form the trail already uses
        if location = klass.source_location
          lux.files_in_use location.is_a?(Array) ? location.join(':') : location
        end

        # no restore: a body ends routing, and an error needs the innermost router
        lux.var[:lux_router] = router
        router.send :run_mounted, action_name, self.class

        return if lux.response.body?

        raise Lux.error.not_found Lux.debug?('404 Not Found') { "#{klass} matched but rendered nothing" }
      end

      def router_class name
        ROUTER_CLASS_CACHE[name] ||= ('%s_router' % name).classify.constantize
      end

      # Compile a plugin routes.rb into a proc once and instance_exec it per
      # request (a string instance_eval recompiled it every time). In reload
      # mode a changed file is recompiled.
      def eval_plugin_routes path
        mtime  = ::File.mtime(path) if Lux.reload?
        cached = PLUGIN_ROUTE_PROCS[path]

        unless cached && cached[0] == mtime
          source = ::File.read(path)
          cached = PLUGIN_ROUTE_PROCS[path] = [mtime, eval("proc do\n#{source}\nend", TOPLEVEL_BINDING, path, 0)]
        end

        instance_exec(&cached[1])
      end

      # Resourceful action resolution from the remaining route cursor path.
      # The action is the last segment that is not a classified id, so it
      # reads straight off the tail of the URL:
      #
      #   /users               -> :index
      #   /users/edit          -> :edit
      #   /users/123           -> :show   (nav.ref == '123')
      #   /users/123/edit      -> :edit   (nav.ref == '123')
      #   /users/posts/123     -> :posts
      #   /users/foo/bar       -> :bar
      #
      # Actions that need the id read `nav.ref`; there is no separate `_ref`
      # action name.
      def resourceful_action remaining
        return :index if remaining.empty?

        (remaining.reverse.find { |s| !s.is_a?(Nav::Base) } || :show).to_sym
      end
    end
  end
end
