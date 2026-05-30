module Lux
  class Application
    module Routes
      # Cached controller class lookups: 'main/users' => Main::UsersController
      # Persists until full process restart.
      CONTROLLER_CLASS_CACHE = {}

      # generate get, get?, post, post? ...
      # get {}
      # get foo: 'main/bar', only: [:show], except: [:index]
      %w{get head post delete put patch}.each do |m|
        define_method('%s?' % m) do |*args, &block|
          cm = lux.request.request_method
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

      # Matches if there is no further segment in the route cursor.
      # ```
      # root 'main#index'
      # ```
      def root target
        call target unless lux.route.root
      end

      # Pure predicate against nav root - delegates to Lux::Application::Nav#root?
      # root?(:admin) -> true if /admin/...
      def root? name
        lux.nav.root? name
      end

      # Absolute-path match. Captures `:var` placeholders into params.
      # ```
      # match '/:city/people', Main::PeopleController
      # ```
      # Advances the route cursor by the number of segments consumed, so
      # lux.route.consumed reflects the matched prefix (needed for sub-mounts
      # like Lux::Api to derive their own mount_on).
      def match base, target
        base = base.split('/').slice(1, 100)

        base.each_with_index do |el, i|
          if el[0,1] == ':'
            lux.params[el.sub(':','').to_sym] = lux.nav.path[i]
          else
            return unless el == lux.nav.path[i]
          end
        end

        lux.route.with_scope(base.length) { call target }
      end

      # Strict, length-exact path match for per-action `route` annotations.
      # Returns true (and binds captures) on success, false otherwise. No
      # dispatch - the caller decides what to do with a match.
      #
      # `:ref` captures bind both `nav.params[:ref]` and `nav.ref` so the
      # controller's existing ref convenience works unchanged.
      def action_route_match? pattern
        pattern_parts = pattern.split('/').reject(&:empty?)
        nav_parts     = lux.nav.path.compact
        return false unless pattern_parts.length == nav_parts.length

        captures = {}
        pattern_parts.each_with_index do |el, i|
          if el.start_with?(':')
            captures[el[1..].to_sym] = nav_parts[i]
          else
            return false unless el == nav_parts[i]
          end
        end

        captures.each do |name, value|
          lux.params[name] = value
          lux.nav.ref      = value if name == :ref && lux.nav.respond_to?(:ref=)
        end
        true
      end

      # Matches given subdomain name
      def subdomain name
        return unless lux.nav.subdomain == name.to_s
        yield
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
      # Equivalent forms:
      # ```
      # map 'adm' do; map 'admin'; end
      # map 'adm', 'admin'
      # map adm: :admin
      # ```
      #
      # Resourceful examples (after `nav.path(:ref) { ... }` canonicalization):
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
      def map route_object = nil, target = nil, &block
        return if lux.response.body?

        # Block form: map 'admin' do ... end
        if block_given?
          if route_match?(route_object)
            lux.route.with_scope(1) { instance_exec(lux.route.root, &block) }
          end
          return
        end

        # Error rescue blocks historically used `map 'promo#app_error'` as a
        # shorthand for `call`; keep that side-channel behavior without making
        # normal one-argument routes unconditional.
        if target.nil? && !route_object.is_hash? && instance_variable_defined?(:@error)
          return catch(:done) { call route_object }
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
            if route_match?(m)
              lux.route.with_scope(1) { catch(:done) { call target_value } }
            end
          end
          return
        end

        # Standard match
        if route_match?(match_value)
          lux.route.with_scope(1) { catch(:done) { call target_value } }
        end
      end

      # Calls target controller and dispatches action.
      #
      # Unconditional dispatch — does not check route_match. Use this inside
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

        action    = action.gsub('-', '_').to_sym if action && action.is_a?(String)
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
          return lux.response.rack object, mount_at: mount_at
        end

        if [Module, Class].include?(object.class) && object.respond_to?(:call)
          lux.response.rack object
        end

        if object.respond_to?(:source_location)
          lux.files_in_use object.source_location
        end

        opts   ||= {}
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
          object.action action.to_sym, ivars: instance_variables_hash
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

        instance_eval ::File.read(path), path, 1
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
          instance_eval ::File.read(path), path, 1
        end
      end

      # Pure predicate: checks if the current route cursor's root matches (no side effects)
      def route_match? route
        root = lux.route.root.to_s
        case route
        when String then root == route.sub(/^\//,'')
        when Symbol then route.to_s == root
        when Regexp then !!(route =~ root)
        when Array  then !!route.map(&:to_s).include?(root)
        else false
        end
      end

      # Resourceful action resolution from the remaining route cursor path.
      #
      # Rules:
      # * empty                              -> :root
      # * [:ref] (single)                    -> :show_ref
      # * single segment X (not :ref)        -> :X
      # * 2+ segments, walk path[1..]:
      #     first non-:ref                   -> :<base>
      #     all :ref                         -> :show
      # * If any :ref was in the path        -> append `_ref` to the resolved action
      #
      # The `_ref` suffix lets controllers cleanly split ID-bearing flows from
      # collection flows without action collisions:
      #   /users               -> :root
      #   /users/edit          -> :edit
      #   /users/123           -> :show_ref
      #   /users/123/edit      -> :edit_ref
      #   /users/foo/bar       -> :foo
      #   /users/123/foo/bar   -> :foo_ref
      def resourceful_action remaining
        return :root if remaining.empty?

        has_ref = remaining.include?(:ref)

        base =
          if remaining.length == 1
            remaining[0] == :ref ? :show : remaining[0].to_sym
          else
            rest = remaining[1..]
            found = rest.find { |s| s != :ref }
            found ? found.to_sym : :show
          end

        has_ref ? :"#{base}_ref" : base
      end
    end
  end
end
