module Lux
  module Ref
    # An id format, and the nav.path element nav.map_path puts in place of an
    # id segment. It is a String reading 'ref' - the route shape `map :ref`
    # and auto templates (boards/ref/edit.haml) match - and #value is the id.
    # A URL segment literally spelled "ref" is a plain String, never a Base.
    #
    # A subclass is a ref format. Build an instance and ask it:
    #
    #   Lux::Ref::Short.new(segment).valid?    # does it look like this format
    #   Lux::Ref::Short.new.generate.value     # a fresh id
    #   Lux::Ref::Short.new.extract(segment)   # the id a URL segment carries, or nil
    class Base < ::String
      attr_reader :value, :attrs

      # Value is stored raw. A map_path block may return anything; whatever it
      # returns is what nav.ref hands back.
      #
      # attrs parameterise the format (see Lux::Ref.register) - `upcase: true`,
      # `length: 26`. Subclasses read them through #attrs.
      def initialize value = nil, **attrs
        super('ref')
        @value = value
        @attrs = attrs
        freeze
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

      # The id `segment` carries in this format, or nil. nav.map_path with no
      # block asks this. Goes through the format, so an upcase family upcases.
      def extract segment
        ref = with(segment)
        ref.value if ref.valid?
      end

      def inspect
        '#<%s %s>' % [self.class.to_s.split('::').last, @value.inspect]
      end
    end
  end
end
