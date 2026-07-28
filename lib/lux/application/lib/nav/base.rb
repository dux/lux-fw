module Lux
  class Application
    class Nav
      # A URL path segment that a classifier recognised as an id.
      #
      # nav.path holds plain Strings for ordinary segments and a Base subclass
      # instance for classified ones. There is no placeholder symbol: the value
      # travels with the segment, so rewriting nav.path can no longer desync it
      # from a side array, and nav.refs is derived rather than stored.
      #
      # A subclass is a ref *format*. Both hooks are instance methods - you build
      # an object and ask it:
      #
      #   seg = Nav::RefString.new(url_segment)
      #   seg.valid?              # does it look like this format
      #   Nav::RefString.new.generate   # a new instance with a fresh value
      #
      # The router matches `:ref` against these by type (see Route#match_segment?),
      # so a literal URL segment spelled "ref" is not one.
      class Base
        # Named formats. An app declares which one it uses with
        # Lux.config.ref_format; everything that needs to know what an id looks
        # like - the router, Lux::Utils::Ref, Lux::Type::RefType, load_models -
        # resolves through here rather than naming a class.
        REGISTRY ||= {}

        class << self
          # Nav::Base.register :string, RefString
          # Nav::Base.register :app_ref, RefString, upcase: true, length: 26
          #
          # Attributes registered here are the format's defaults, so a family of
          # variants needs one class and several names rather than a subclass
          # each.
          def register name, klass, **attrs
            REGISTRY[name.to_sym] = [klass, attrs]
          end

          # Accepts a registered name, a `{ name => attrs }` pair (the shape a
          # config.yaml hash arrives in), or a Base subclass. Returns
          # [klass, attrs].
          def resolve format
            case format
            when nil            then default
            when ::Symbol, ::String
              REGISTRY[format.to_sym] or
                raise ArgumentError, 'Unknown ref format %p - registered: %s' % [format, REGISTRY.keys.join(', ')]
            when ::Class
              raise ArgumentError, '%s is not a Nav::Base' % format unless format <= Base
              [format, {}]
            else
              # { string: { upcase: true } } - registered defaults, then overrides
              raise ArgumentError, 'Unsupported ref format %p' % format unless format.respond_to?(:first)
              name, attrs = format.first
              klass, defaults = resolve(name)
              [klass, defaults.merge((attrs || {}).transform_keys(&:to_sym))]
            end
          end

          # The app-wide declared format. Read per call, not memoized, so a spec
          # (or a host that reconfigures at boot) is not stuck with the first
          # value seen.
          def default
            resolve Lux.config[:ref_format] || :string
          end

          # Build an instance of the declared (or given) format.
          def build value = nil, format: nil, path_before: nil
            klass, attrs = resolve(format)
            klass.new value, path_before: path_before, **attrs
          end
        end

        attr_reader :value, :path_before, :attrs

        # Value is stored raw. A classifier block may return anything; whatever
        # it returns is what nav.ref hands back.
        #
        # path_before is the segment that sat immediately left of this one when
        # nav.map_path classified it - the resource name in /boards/<ref>.
        # Captured then, so a later nav.path rewrite does not move it. nil at
        # position 0, and itself a Base when two ids are adjacent.
        #
        # attrs parameterise the format (see .register) - `upcase: true`,
        # `length: 26`. Subclasses read them through #attrs.
        def initialize value = nil, path_before: nil, **attrs
          @value       = value
          @path_before = path_before
          @attrs       = attrs
        end

        # A new instance of the same format, carrying a freshly minted value.
        def generate
          raise NotImplementedError, '%s#generate' % self.class
        end

        # Does #value look like this format?
        def valid?
          raise NotImplementedError, '%s#valid?' % self.class
        end

        # varchar width for Lux::Type::RefType, so the column and the router
        # cannot disagree about how wide an id is.
        def db_limit
          raise NotImplementedError, '%s#db_limit' % self.class
        end

        # A sibling instance - same format, same attrs, different value.
        def with value
          self.class.new value, **@attrs
        end

        # The segment renders as its value, so nav.pathname and nav.to_s print
        # the URL as it arrived. `:ref` matching does not go through here.
        def to_s
          @value.to_s
        end

        def inspect
          '#<%s %s>' % [self.class.to_s.split('::').last, @value.inspect]
        end

        # One-way against a String: `ref == 'abc'` is true, `'abc' == ref` is
        # not, because String#== rejects a non-String and there is deliberately
        # no #to_str here to coerce it. Keep the segment on the left, or compare
        # #value. Router matching does not rely on this - see Route#match_segment?.
        def == other
          other.is_a?(Base) ? value == other.value : to_s == other.to_s
        end
      end
    end
  end
end
