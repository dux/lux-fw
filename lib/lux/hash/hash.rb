module Lux
  # Hash with indifferent access.
  #
  # Lux::Hash         - class (subclass of ::Hash) with included Methods
  # Lux::Hash::Methods - module also extended onto raw Hash values on access
  # Lux::Hash(...)     - helper for building named-option hashes (see bottom)
  # Hash#to_lux_hash   - convert any Hash to Lux::Hash (or to a dyn Struct)
  class Hash < ::Hash
    STRUCTS ||= {}

    module Methods
      def initialize hash = nil
        if hash
          hash.each { |k,v| self[k] = v }
        end
      end

      # overload common key names so they act as data accessors
      %i(size length zip minmax store cycle chunk sum uniq chain).each do |el|
        define_method el do
          self[el]
        end
      end

      # all keys are coerced to String. Lookups follow suit, so
      # h[:foo], h['foo'] and h.foo all hit the same slot. Integer /
      # Class keys round-trip via to_s (h[1] stored as "1", h[1] and
      # h['1'] both read it back). nil / empty keys are rejected on write.
      def [] key
        super(key.to_s)
      end

      def []= key, value
        k = key.to_s
        raise ArgumentError, 'Lux::Hash key cannot be nil or empty' if k.empty?
        value = Lux::Hash.new(value) if value.is_a?(::Hash) && !value.is_a?(Lux::Hash)
        super(k, value)
      end

      def delete key
        super(key.to_s)
      end

      def key? key
        super(key.to_s)
      end
      alias_method :has_key?, :key?
      alias_method :include?, :key?
      alias_method :member?,  :key?

      def fetch key, *args, &block
        super(key.to_s, *args, &block)
      end

      def values_at *keys
        super(*keys.map(&:to_s))
      end

      def assoc key
        super(key.to_s)
      end

      # we never return array from hash, ruby internals
      def to_ary
        nil
      end

      # direct :key access (h.key) or fetch by name (h.key(:foo))
      def key name = nil
        self[name.nil? ? :key : name]
      end

      # deep clone with no shared references
      def clone
        Marshal.load(Marshal.dump(self))
      end

      def merge hash
        dup.tap do |h|
          hash.each { |k, v| h[k] = v }
        end
      end

      def merge! hash
        hash.each { |k, v| self[k] = v }
      end

      def dig *args
        root = self
        while args[0]
          root = root[args.shift]
          return if root.nil?
        end
        root
      end

      def method_missing name, *args, &block
        strname = name.to_s

        # Ruby 4 returns a frozen string from Symbol#to_s; chomp/end_with?
        # avoid in-place mutation (and the regex engine) on the hot path.
        last = strname[-1]

        if last == '?'
          # h.foo? - truthy unless value is nil, false, 'false' or 0
          ![nil, false, 'false', 0].include?(self[strname.chomp('?')])
        elsif last == '='
          # h.foo = :bar
          self[strname.chomp('=')] = args.first
        else
          value = self[strname]

          if value.nil?
            if block
              self[strname] = block
            elsif key?(strname)
              nil
            else
              raise NoMethodError.new('%s not defined in Lux::Hash' % strname)
            end
          else
            if value.class == Array
              value.map! {|el| el.class == ::Hash ? Lux::Hash.new(el) : el }
            end
            value
          end
        end
      end
    end

    include Methods

    # DSL collector used by Lux::Hash(...) helper below.
    #
    # Builds an enum-shaped hash with two access paths off the SAME value:
    #   * native key  : h[code] -> value         (plain code -> value storage)
    #   * named call  : h.NAME  -> value         (singleton method on the hash)
    # The constant NAME never appears as a hash key — to_h stays clean.
    class NamedOptions
      UPCASE_NAME ||= /\A[A-Z][A-Z0-9_]*\z/

      def initialize hash, &block
        @hash  = hash
        @block = block
      end

      def set constant, code, value
        @block.call constant.to_s, code, value
        @hash[code] = value
        @hash.define_singleton_method(constant) { value }
      end

      def method_missing name, key_val
        unless name.to_s.match?(UPCASE_NAME)
          raise ArgumentError, 'Lux::Hash named option must be uppercase (got %s)' % name
        end
        self.set name, key_val.keys.first, key_val.values.first
      end
    end
  end

  # Build an enum hash. Always call with parens — `Lux::Hash` alone is a
  # constant lookup and Ruby won't attach the block to it. The returned
  # hash is always frozen.
  #
  #   # plain enum: storage is { "1" => "Active" }, plus h.ACTIVE -> "Active"
  #   OPTS = Lux::Hash() do |opt|
  #     opt.ACTIVE 1 => 'Active'
  #   end
  #   OPTS[1]      # => "Active"
  #   OPTS.ACTIVE  # => "Active"
  #
  #   # also expose Foo.status method returning the hash
  #   class Foo
  #     STATUS = Lux::Hash(self, method: :status) do |opt|
  #       opt.ACTIVE 1 => 'Active'
  #     end
  #   end
  #
  #   # also create Foo::STATUS_ACTIVE = 1
  #   class Foo
  #     STATUS = Lux::Hash(self, constants: :status) do |opt|
  #       opt.ACTIVE 1 => 'Active'
  #     end
  #   end
  def self.Hash klass = nil, opts = nil
    raise ArgumentError, 'Block not provided' unless block_given?

    if klass.class == ::Hash
      opts  = klass
      klass = nil
    end

    opts ||= {}
    hash   = Lux::Hash.new

    named_opts = Lux::Hash::NamedOptions.new hash do |constant, code, _value|
      if opts[:constants]
        raise 'Host class not given (call as Lux::Hash self, constants: ...)' unless klass
        klass.const_set "#{opts[:constants]}_#{constant}".upcase, code
      end
    end

    yield named_opts

    klass.define_singleton_method(opts[:method]) { hash } if opts[:method]

    hash.freeze
  end
end

class Hash
  # { foo: :bar }.to_lux_hash            - wrap as Lux::Hash
  # { foo: :bar }.to_lux_hash :foo, :bar - cast to a dynamic Struct
  def to_lux_hash *args
    if args.first.nil?
      Lux::Hash.new self
    else
      list = args.flatten
      name = 'DynStruct_' + list.join('_')
      Lux::Hash::STRUCTS[name] ||= ::Struct.new(name, *list)
      Lux::Hash::STRUCTS[name].new **self
    end
  end
end
