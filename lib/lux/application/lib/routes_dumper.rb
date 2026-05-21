# Shadow-executor that re-runs the application's routes-callback procs
# against a recording instance, producing a flat list of mounted routes.
#
# The router is fully imperative (map/root/match dispatch happen at request
# time), so there is no static registry to read. Instead we replay the same
# procs that get registered into @class_callbacks_routes - but route_match?
# is always true, response.body? always false, and `call` records instead of
# dispatching. Every branch is descended.
#
# Limitations:
# * conditional branches based on runtime data (request method, host,
#   current user, etc.) get descended unconditionally - the dump shows
#   "everything that could match", not "what will match for THIS request"
# * `call :symbol` (dispatch to a method) is recorded as [dynamic] since
#   we cannot statically resolve where it goes
# * any code inside routes blocks that hits Lux::Current state is no-op'd
#   via the NoopCurrent stub (see #with_stub_current)

module Lux
  class Application
    class RoutesDumper
      Entry ||= Struct.new(:verb, :path, :target, :source, keyword_init: true)

      attr_reader :entries

      def initialize app_class
        @app_class = app_class
        @path      = []
        @verb      = '*'
        @entries   = []
        @source    = nil
      end

      def self.dump app_class = nil
        new(app_class || Lux.app).dump
      end

      def dump
        store = @app_class.instance_variable_get(:@class_callbacks_routes) || {}
        return @entries if store.empty?

        with_stub_current do
          # iterate a snapshot - some wrapped procs would otherwise re-enter
          # the singleton DSL and mutate the hash mid-walk
          store.to_a.each do |source, value|
            @source = source
            case value
            when Proc
              instance_exec(&value)
            when Array
              # routes :method_name form - record as a callback reference
              record verb: '*', path: '/*', target: '[callback] %s' % value.inspect
            end
          end
        end

        @entries
      end

      # --- routing DSL stubs ---

      def root target
        record verb: 'GET', path: build_path, target: stringify(target)
      end

      def match base, target
        record verb: '*', path: base, target: stringify(target)
      end

      def map route_object = nil, target = nil, &block
        if block_given?
          push_segment(route_object)
          instance_exec(@path.last, &block)
          @path.pop
        else
          # NOTE: inside module Lux, bare `Hash` resolves to Lux::Hash, so we
          # use the obj.is_hash? predicate from lib/overload/object.rb.
          full_target =
            if target then target
            elsif route_object.is_hash? then route_object.values.first
            else route_object
            end

          # absolute-path map - either positional string or hash with string key
          abs =
            if route_object.is_a?(::String) && route_object.start_with?('/')
              route_object
            elsif route_object.is_hash?
              k = route_object.keys.first
              k.is_a?(::String) && k.start_with?('/') ? k : nil
            end
          return match(abs, full_target) if abs

          push_segment(route_object)
          record verb: @verb, path: build_path, target: stringify(full_target)
          @path.pop
        end
      end

      def call object = nil, action = nil, *_
        target =
          case object
          when Symbol then '[dynamic] %s' % object
          when Class, String then action ? '%s#%s' % [object, action] : stringify(object)
          when Proc, Array then '[inline]'
          else stringify(object)
          end
        record verb: @verb, path: build_path, target: target
      end

      def subdomain name, &block
        prev_path = @path
        @path = ['[%s.]' % name]
        # block was lexically captured at app-class-eval time; rebind self
        # to the dumper so map/root/etc. inside record instead of mutating
        # the original class's callback hash.
        instance_exec(&block) if block
        @path = prev_path
      end

      def mount opts
        target = opts.keys.first
        prefix = opts.values.first
        record verb: '*', path: prefix.to_s + '/*', target: '[mounted] %s' % stringify(target)
      end

      def favicon path
        record verb: 'GET', path: '/favicon.ico', target: '[favicon] %s' % path
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
        define_method('%s?' % verb) do |*args, &block|
          prev = @verb
          @verb = verb.upcase
          if block
            # rebind block to the dumper (see #subdomain note)
            instance_exec(&block)
          elsif args.first
            map(*args)
          end
          @verb = prev
        end
      end

      # Catch-all for arbitrary instance method calls inside routes blocks
      # (e.g. helper defs, side-effect callbacks like nav.path(:ref) { ... }
      # that pre-process the request). Return a chainable noop so calls
      # like `request.path` inside conditionals do not raise.
      def method_missing _name, *_args, **_kw, &_block
        NoopCurrent.new
      end

      def respond_to_missing? _name, _priv = false
        true
      end

      private

      def push_segment obj
        # bare class names inside module Lux resolve to Lux::* aliases - guard
        # with predicates or fully-qualified ::Class names
        seg =
          if obj.nil?               then nil
          elsif obj.is_a?(::String) then obj.split('#').first
          elsif obj.is_a?(::Symbol) then obj.to_s
          elsif obj.is_hash?
            key = obj.keys.first
            key.is_a?(::String) ? key.split('#').first : key.to_s
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
        when nil           then '(none)'
        when String, Symbol then x.to_s
        when Class         then x.to_s
        when Proc          then '[proc]'
        when Array
          if x[0].is_a?(Class) || x[0].is_a?(String)
            '%s#%s' % [x[0], x[1]]
          else
            x.inspect
          end
        else
          x.to_s
        end
      end

      def record verb:, path:, target:
        @entries << Entry.new(verb: verb, path: path, target: target, source: @source)
      end

      # Provide a no-op stub for `lux` calls inside routes blocks so things
      # like `routes { lux.response.body '...' unless lux.response.body? }`
      # do not blow up while we replay.
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
      end
    end
  end
end
