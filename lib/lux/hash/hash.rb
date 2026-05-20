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

      def [] key
        key = key.to_s unless key.respond_to?(:to_sym)
        data = super(key.to_s) || super(key.to_sym)
        data.extend Lux::Hash::Methods if data.is_a?(::Hash)
        data
      end

      def []= key, value
        key = key.to_s unless key.class == Symbol
        delete(key.to_s).nil? && delete(key.to_sym)
        super key, value
      end

      def delete key
        data = super(key)
        skey = key.to_s
        data = super(skey) if data.nil?
        data = super(skey.to_sym) if data.nil? && key.class != Symbol
        data
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
          hash.each { |k, v| h[k.to_s] = v }
        end
      end

      def merge! hash
        hash.each { |k, v| self[k.to_s] = v }
      end

      def each &block
        to_a.each do |key, data|
          data.extend Lux::Hash::Methods if data.is_a?(::Hash)
          block.call key, data
        end

        self
      end

      def dig *args
        root = self
        while args[0]
          key = args.shift
          root = root[key] || root[key.to_s]
          return if root.nil?
          root = Lux::Hash.new root if root.class == ::Hash
        end
        root
      end

      def values
        super.map do |el|
          el.class == ::Hash ? Lux::Hash.new(el) : el
        end
      end

      def method_missing name, *args, &block
        strname = name.to_s

        if strname.sub!(/\?$/, '')
          # h.foo?
          !!self[strname]
        elsif strname.sub!(/=$/, '')
          # h.foo = :bar
          self[strname] = args.first
        else
          value = self[strname]
          value = self[strname.to_sym] if value.nil?

          if value.nil?
            if block
              self[strname.to_s] = block
            else
              if key?(strname) || key(strname.to_sym)
                nil
              else
                raise NoMethodError.new('%s not defined in Lux::Hash' % strname)
              end
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
    class NamedOptions
      def initialize hash, &block
        @hash  = hash
        @block = block
      end

      def set constant, code, value
        @block.call constant.to_s, code, value
        @hash[constant.to_s] = code
        @hash[code]          = value
      end

      def method_missing code, key_val
        self.set code, key_val.keys.first, key_val.values.first
      end
    end
  end

  # Build a named-option hash. Always call with parens — `Lux::Hash` alone is
  # a constant lookup and Ruby won't attach the block to it.
  #
  #   # plain hash
  #   OPTS = Lux::Hash() do |opt|
  #     opt.ACTIVE 1 => 'Active'
  #   end
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

    hash.freeze unless opts[:freeze] == false

    hash
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
