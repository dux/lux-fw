module Lux
  class Schema
    SCHEMA_STORE ||= {}
    REFS         ||= {}   # named schemas referenced by API params - the one documented place

    attr_reader :klass, :opts

    # set by the db plugin when a model registers its schema (Lux.schema name,
    # type: :model); lets nested model validation reach back to the model's
    # api_schema. nil for ad-hoc / derived schemas.
    attr_accessor :model_klass

    # accepts dsl block to define schema
    # or define: keyword for internal use (only/except)
    def initialize name, opts = nil, define: nil, &block
      @opts = opts || {}

      if define
        @schema = define
      elsif block
        @schema = Define.new(&block)

        if name
          @klass = name
          SCHEMA_STORE[name] = self
        end
      else
        raise "Use Lux.schema(:name) to load stored schema"
      end
    end

    # returns new schema with only specified keys
    def only *keys
      keys = keys.map(&:to_sym)
      filtered = rules.select { |k, _| keys.include?(k) }
      self.class.new(nil, define: Define.new(filtered))
    end

    # returns new schema without specified keys
    def except *keys
      keys = keys.map(&:to_sym)
      filtered = rules.reject { |k, _| keys.include?(k) }
      self.class.new(nil, define: Define.new(filtered))
    end

    # tag this schema with a documentation name (used by API introspection to
    # list it once in the schemas map and reference it from params by name)
    def as name
      @klass = name.to_s
      self
    end

    # force every field optional (clears `required`), mutating in place.
    # rebuilds rules with fresh opt hashes so a derived api/param schema can be
    # made lenient without touching the source model schema it was copied from.
    def set_all_optional!
      @schema = Define.new(rules.transform_values { |o| o.merge(required: false) })
      self
    end

    # validates any instance object with hash variable interface
    # it also coerces values
    def validate object, options = nil
      @object = object
      @errors = {}
      options ||= {}

      # input validation (API params, nested model fields) coerces types and
      # filters keys but does not enforce presence - mandatory columns are the
      # model/DB's job on save. Pass required: false to skip required errors.
      @skip_required = options[:required] == false

      strip_undefined_keys! if options[:strict] && object.is_hash?

      @schema.rules.each do |field, raw_opts|
        field = field.to_sym
        opts = resolve_opts(raw_opts)

        read_value field            # normalize string keys to symbol before defaulting
        apply_default field, opts
        value = read_value field

        value =
          if opts[:array]
            validate_array field, value, opts
          else
            validate_scalar field, value, opts
          end

        # present empty string values as nil
        @object[field] = blank?(value) ? nil : value
      end

      if @errors.any? && block_given?
        @errors.each { |k, v| yield(k, v) }
      end

      @errors
    end

    def valid? object
      validate(object).empty?
    end

    # returns raw db rules like [:timestamps] or [:add_index, :code]
    def db_rules
      @schema.db_rules
    end

    # enum definitions captured by the db plugin's `enum` DSL keyword
    # ([] when the db plugin isn't loaded or no enums were declared)
    def enums
      @schema.respond_to?(:enums_list) ? @schema.enums_list : []
    end

    # returns field, db_type, db_opts
    # virtual fields are model setters, not columns - skipped so db:am ignores them
    def db_schema
      @schema.rules.reject { |_, opts| opts[:virtual] }.map do |field, opts|
        type, db_opts = Lux::Type.load(opts[:type]).new(nil, opts).db_field
        db_opts[:array] = true if opts[:array]
        [field, type, db_opts]
      end
    end

    # iterate through all the rules via block interface
    # schema.rules do |field, opts|
    # schema.rules(:url) do |field, opts|
    def rules filter = nil, &block
      return @schema.rules unless filter
      out = @schema.rules
      out = out.select { |k, v| v[:type].to_s == filter.to_s || v[:array_type].to_s == filter.to_s } if filter
      return out unless block_given?

      out.each { |k, v| yield k, v }
    end
    alias :to_h :rules

    private

    # remove keys not defined in schema
    def strip_undefined_keys!
      defined_keys = @schema.rules.keys.map(&:to_s)
      @object.delete_if { |k, _| !defined_keys.include?(k.to_s) }
    end

    # dup opts so Proc resolution does not mutate stored schema
    def resolve_opts raw_opts
      opts = raw_opts.dup
      opts.each do |k, v|
        opts[k] = @object.instance_exec(&v) if v.is_a?(Proc)
      end
      opts
    end

    def apply_default field, opts
      if !opts[:default].nil? && @object[field].to_s.blank?
        @object[field] = opts[:default]
      end
    end

    # read value from object, normalizing string keys to symbols for Hash
    def read_value field
      if @object.respond_to?(:key?)
        if @object.key?(field)
          @object[field]
        elsif @object.key?(field.to_s)
          @object[field] = @object.delete(field.to_s)
        end
      else
        @object[field]
      end
    end

    def validate_array field, value, opts
      unless value.respond_to?(:each)
        delimiter = opts[:delimiter] || /\s*[,\n]\s*/
        value = value.to_s.split(delimiter)
      end

      value = value
        .flatten
        .map { |el| el.to_s == '' ? nil : coerce_value(field, el, opts) }
        .compact

      value = Set.new(value).to_a unless opts[:duplicates]

      max_count = opts[:max_count] || 100
      add_error(field, 'Max number of array elements is %d, you have %d' % [max_count, value.length], opts) if value.length > max_count
      add_error(field, 'Min number of array elements is %d, you have %d' % [opts[:min_count], value.length], opts) if opts[:min_count] && value.length < opts[:min_count]

      add_required_error field, value.first, opts
      value
    end

    def validate_scalar field, value, opts
      value = nil if value.to_s == ''

      allowed = opts[:allow] || opts[:allowed] || opts[:values]
      if value && allowed && !allowed.map(&:to_s).include?(value.to_s)
        add_error field, 'Value "%s" is not allowed' % value, opts
      end

      value = coerce_value field, value, opts
      add_required_error field, value, opts
      value
    end

    # coerce a single value through its type class
    def coerce_value field, value, opts
      klass = Lux::Type.load(opts[:type])
      check = klass.new value, opts
      check.db_value
    rescue TypeError => e
      if e.message[0] == '{'
        JSON.parse(e.message).each do |key, msg|
          add_error [field, key].join('.'), msg, opts
        end
      else
        add_error field, e.message, opts
      end
    rescue JSON::ParserError => e
      add_error field, e.message, opts
    end

    # adds error to hash, prefixing with field name if message starts lowercase
    def add_error field, msg, opts
      if @errors[field]
        @errors[field] += ", %s" % msg
      else
        if msg && msg[0, 1].downcase == msg[0, 1]
          field_name = opts[:name] || field.to_s.sub(/_id$/, "").capitalize
          msg = "%s %s" % [field_name, msg]
        end

        @errors[field] = msg
      end
    end

    def add_required_error field, value, opts
      return if @skip_required
      return unless opts[:required] && value.nil?
      msg = opts[:required].class == TrueClass ? "is required" : opts[:required]
      add_error field, msg, opts
    end

    def blank? value
      value.to_s.sub(/\s+/, '') == ''
    end
  end
end
