# Shadow-executor that replays a router's `route do` block against a
# recording instance, producing a flat list of mounted routes.
#
# The router is fully imperative (map/root dispatch happen at request time),
# so there is no static registry to read. Instead we replay the route block
# with `map` / `root` recording instead of dispatching. Every branch is
# descended, and a mounted router class (`map 'admin', AdminRouter`) is
# replayed in place, once.
#
# Limitations:
# * conditional branches based on runtime data (request method, host,
#   current user, etc.) get descended unconditionally - the dump shows
#   "everything that could match", not "what will match for THIS request"
# * helper methods called from the route block are no-ops (method_missing),
#   so maps inside them are not listed
# * any code inside route blocks that hits Lux::Current state is no-op'd
#   via the NoopCurrent stub (see #with_stub_current)
# * a block that raises on dumper state (a guard reading an unset ivar such as
#   `@space.can.update!`) ends that block only; routes after the raise inside
#   the same block are not listed

module Lux
  class Router
    class RoutesDumper
      Entry ||= Struct.new(:verb, :path, :target, :source, keyword_init: true)

      attr_reader :entries

      def initialize router_class
        @router_class = router_class
        @path         = []
        @verb         = '*'
        @entries      = []
        @source       = nil
        @visited      = Set.new
      end

      def self.dump router_class = nil
        new(router_class || Lux.router).dump
      end

      def dump
        with_stub_current { replay @router_class } if @router_class.route_block
        @entries
      end

      # --- routing DSL stubs ---

      def root target, **_opts
        record verb: 'GET', path: build_path, target: stringify(target)
      end

      def map *args, **_opts, &block
        if block
          # the router passes the segment AFTER the ones it just consumed
          # (lux.route.root inside the new scope); there is no such segment
          # while dumping, so pass nil. A scope that maps nothing (a guard,
          # an inline render) is listed as [block].
          with_segments(args) do
            count = @entries.length
            replay_block(nil, &block)
            record verb: @verb, path: build_path, target: '[block]' if @entries.length == count
          end
          return
        end

        target = args.pop

        if args.length == 1 && args.first.is_a?(::String) && args.first.start_with?('/')
          record verb: '*', path: args.first, target: stringify(target)
        else
          with_segments(args) { dump_target target }
        end
      end

      def auto
        record verb: @verb, path: build_path, target: '[auto]'
      end

      def action *_
        record verb: @verb, path: build_path, target: '[action]'
      end

      def subdomain name, &block
        prev_path = @path
        @path = ['[%s.]' % name]
        # block was lexically captured at class-eval time; rebind self to the
        # dumper so map/root/etc. inside record instead of dispatching.
        instance_exec(&block) if block
        @path = prev_path
      end

      # Locale policy does not change the route tree - descend so nested
      # routes are still listed.
      def localized value = true, force: false, geo: true, &block
        instance_exec(&block) if block
      end

      def plugin_route name
        record verb: '*', path: build_path, target: '[plugin] %s' % name
      end

      def plugin_routes
        Lux::Plugin::PLUGIN.each_value do |plugin|
          next unless ::File.exist?(::File.join(plugin.folder, 'routes.rb'))
          record verb: '*', path: build_path, target: '[plugin] %s' % plugin.name
        end
      end

      %w(get head post delete put patch).each do |verb|
        define_method('%s?' % verb) do |*args, **opts, &block|
          prev = @verb
          @verb = verb.upcase
          if block
            # rebind block to the dumper (see #subdomain note)
            instance_exec(&block)
          elsif args.first
            map(*args, **opts)
          end
          @verb = prev
        end
      end

      # Catch-all for arbitrary instance method calls inside route blocks
      # (e.g. helper defs, side-effect callbacks like nav.map_path { ... }
      # that pre-process the request). Return a chainable noop so calls
      # like `request.path` inside conditionals do not raise.
      def method_missing _name, *_args, **_kw, &_block
        NoopCurrent.new
      end

      def respond_to_missing? _name, _priv = false
        true
      end

      private

      # A router with a route block of its own is replayed in place, once;
      # anything else is recorded at the current path.
      def dump_target target
        klass = mounted_router(target)

        if klass && !@visited.include?(klass.route_block)
          replay klass
        else
          record verb: @verb, path: build_path, target: stringify(target)
        end
      end

      def replay klass
        block = klass.route_block
        @visited << block
        prev, @source = @source, block.source_location.join(':')
        replay_block(&block)
        @source = prev
      end

      def replay_block *args, &block
        instance_exec(*args, &block)
      rescue StandardError
        nil
      end

      # A Router class, or a bare router name ('admin/users' ->
      # Admin::UsersRouter), that has a route block.
      def mounted_router target
        klass =
          if target.is_a?(::Class)
            target
          elsif target.is_a?(::String) && !target.include?('#')
            begin
              ('%s_router' % target).classify.constantize
            rescue NameError
              nil
            end
          end

        klass if klass && klass < Lux::Router && klass.route_block
      end

      def with_segments segments
        pushed = segments.map { push_segment _1 }.compact.length
        yield
      ensure
        @path.pop pushed.to_i
      end

      def push_segment obj
        # bare class names inside module Lux resolve to Lux::* aliases - guard
        # with predicates or fully-qualified ::Class names
        seg =
          if obj.nil?               then nil
          elsif obj.is_a?(::String) then obj
          elsif obj.is_a?(::Symbol) then obj == :ref ? ':ref' : obj.to_s
          elsif obj.is_a?(::Array)  then '[%s]' % obj.map(&:to_s).join('|')
          elsif obj.is_a?(::Regexp) then obj.inspect
          else                           obj.to_s
          end
        @path.push(seg) if seg
      end

      def build_path
        parts = @path.compact.reject { |s| s == '' }
        parts.empty? ? '/' : '/' + parts.join('/')
      end

      def stringify x
        case x
        when nil    then '(none)'
        when Symbol then '#%s' % x
        when Proc   then '[proc]'
        else             x.to_s
        end
      end

      def record verb:, path:, target:
        @entries << Entry.new(verb: verb, path: path, target: target, source: @source)
      end

      # Provide a no-op stub for `lux` calls inside route blocks so things
      # like `lux.response.body?` do not blow up while we replay.
      def with_stub_current
        prev = Thread.current[:lux]
        Thread.current[:lux] = NoopCurrent.new
        yield
      ensure
        Thread.current[:lux] = prev
      end

      class NoopCurrent
        def method_missing(_name, *_args, **_kw, &_block); self; end
        def respond_to_missing?(_name, _priv = false); true; end
        # avoid recursive nil chains on truthy checks (e.g. `unless body?`)
        def body?; false; end
        def path; ''; end
        def request_method; '*'; end
        # Url.current parses request.url, needs a real string
        def url; 'http://localhost/'; end
      end
    end
  end
end
