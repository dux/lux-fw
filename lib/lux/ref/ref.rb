# Lux::Ref - what an id looks like, app-wide. The format is named by
# Lux.config.ref_format; nav.map_path, the :ref column type and model primary
# keys all resolve through here, so they cannot drift apart.
#
#   Lux::Ref.generate      # -> "k3p9x2mq7wd1nb84", or a uuid7, ...
#   Lux::Ref.is?(segment)  # -> true / false
#
# The db plugin reopens this module to add Lux::Ref.models, which needs Sequel.
module Lux
  module Ref
    extend self

    FORMATS ||= {}

    # Lux::Ref.register :string, Lux::Ref::Short
    # Lux::Ref.register :app_ref, Lux::Ref::Short, upcase: true, length: 26
    #
    # Attributes registered here are the format's defaults, so a family of
    # variants needs one class and several names rather than a subclass each.
    def register name, klass, **attrs
      FORMATS[name.to_sym] = [klass, attrs]
    end

    # Accepts a registered name, a `{ name => attrs }` pair (the shape a
    # config.yaml hash arrives in), or a Base subclass. Returns [klass, attrs].
    def resolve format
      case format
      when nil            then default
      when ::Symbol, ::String
        FORMATS[format.to_sym] or
          raise ArgumentError, 'Unknown ref format %p - registered: %s' % [format, FORMATS.keys.join(', ')]
      when ::Class
        raise ArgumentError, '%s is not a Lux::Ref::Base' % format unless format <= Base
        [format, {}]
      else
        # { string: { upcase: true } } - registered defaults, then overrides
        raise ArgumentError, 'Unsupported ref format %p' % format unless format.respond_to?(:first)
        name, attrs = format.first
        klass, defaults = resolve(name)
        [klass, defaults.merge((attrs || {}).transform_keys(&:to_sym))]
      end
    end

    # The app-wide declared format. Read per call, not memoized, so a spec (or
    # a host that reconfigures at boot) is not stuck with the first value seen.
    def default
      resolve Lux.config[:ref_format] || :string
    end

    # An instance of the declared (or given) format.
    def build value = nil, format: nil
      klass, attrs = resolve(format)
      klass.new value, **attrs
    end

    # Extra args go to the format's #generate - Short takes a length.
    def generate *args
      build.generate(*args).value
    end

    def is? text
      build(text).valid?
    end
  end
end
