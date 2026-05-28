module Lux
  class JsonExporter
    EXPORTERS ||= {}
    FILTERS   ||= { before: {}, after: {} }

    class << self
      def define name = nil, &block
        # if name is given, prepend name; otherwise use class name as exporter name
        name = name ? "#{name.to_s.classify}#{to_s}" : to_s

        EXPORTERS[name] = block
      end

      def export name, opts = nil
        new(name, opts || {}).render
      end

      def before &block
        __define_filter :before, &block
      end

      def after &block
        __define_filter :after, &block
      end

      private

      def __define_filter name, &block
        define_method name do
          super() if self.class != Lux::JsonExporter
          instance_exec opts, &block
        end
      end
    end

    attr_accessor :json, :model

    alias :response :json

    def initialize model, opts = {}
      if [String, Symbol].include?(model.class)
        raise ArgumentError, 'model argument is not model instance (it is a %s)' % model.class
      end

      opts[:export_depth]  ||= 2 # default depth; nested recursive exports cap here
      opts[:current_depth] ||= 0
      opts[:current_depth] += 1

      @model = model
      @opts  = opts.to_lux_hash
      @block = __find_exporter
      @json  = {}
    end

    def opts name = nil
      if name
        if @opts[name]
          block_given? ? yield : true
        end
      else
        @opts
      end
    end

    def render
      before
      instance_exec @opts, &@block
      after

      @json
    end

    def merge data
      data.each { |k, v| json[k] = v }
    end

    def before; end

    def after; end

    private

    # export object
    # export :org_users, key: :users
    def export name, local_opts = {}
      return if @opts[:current_depth] > @opts[:export_depth]

      if name.is_a?(Symbol)
        name, cmodel = name, @model.send(name)

        if cmodel.class.to_s.include?('Array')
          cmodel = cmodel.map { |el| self.class.export(el, __opts) }
        end
      else
        underscored = name.class.to_s.underscore.to_sym
        name, cmodel = underscored, name
      end

      @json[name] = if [Array].include?(cmodel.class)
        cmodel
      elsif cmodel.nil?
        nil
      else
        self.class.new(cmodel, __opts(local_opts)).render
      end
    end

    # add property to exporter
    def property name, data = Lux::UNSET, &block
      if block_given?
        hash_data = {}
        data = instance_exec hash_data, &block
        data = hash_data if hash_data.keys.first
      elsif data.equal?(Lux::UNSET)
        data = @model.send(name)
      end

      @json[name] = data unless data.nil?
    end
    alias :prop :property

    def __find_exporter
      base  = (@opts[:exporter] || model.class).to_s.classify
      shape = @opts[:shape]

      self.class.ancestors.map(&:to_s).each do |klass|
        if shape
          block = EXPORTERS["#{shape.to_s.classify}#{klass}"]
          return block if block
        end
        block = EXPORTERS[[base, klass].join] || EXPORTERS[klass]
        return block if block
      end

      raise %[Exporter for class "#{base}" not found.]
    end

    def __opts start = {}
      start.merge(
        export_depth:  @opts[:export_depth],
        current_depth: @opts[:current_depth]
      )
    end
  end
end
