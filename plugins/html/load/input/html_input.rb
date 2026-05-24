# input = HtmlInput.new(User.first)
# input.render :email, value: 'foo@bar.baz'

class HtmlInput
  attr_accessor :type, :opts
  attr_reader :opt

  def [] key
    @opts[key]
  end

  def []= key, value
    @opts[key] = value
  end

  def initialize object=nil, opts={}
    if object.is_a?(Hash)
      opts   = object
      object = nil
    end

    @object = object
    @opt    = opts.dup.freeze
    @opts   = opts.dup

    @opts.delete :disabled if @opts[:disabled].to_s == 'false'
  end

  def tag(*args, **attrs, &block)
    HtmlTag.render_root(self, *args, **attrs, &block)
  end

  # .render :name          # @object.name
  # .render settings: :key # @object.settings[key]
  def render name, opts = {}
    @opts = @opt.merge(opts)
    @name = name

    @opts[:placeholder] ||= 'email...' if @name.to_s.include?('email')
    @opts[:placeholder] ||= 'https://...' if @name.to_s.end_with?('url')
    @opts[:id]          ||= 'i_%s' % Lux.current.uid

    if @object && @object.class.respond_to?(:schema) && [Symbol, Array].include?(@name.class)
      schema = @object.class.schema || raise('Lux schema for object "%s" not found' % @object.class)

      detect_type_from_schema
      apply_schema_rules schema

      if @name.is_a?(Symbol) && @object.respond_to?(:db_schema) && !@opts[:as]
        resolve_collection_from_name
      end

      @opts[:as]    ||= calculate_type
      @opts[:id]    ||= Lux.current.uid
      @opts[:value] ||= @object.send(name) if @object && name.is_a?(Symbol)
      @opts[:value]   = @opts[:default] if @opts[:value].blank?
      @opts[:value]   = @opts[:value].to_f if @opts[:value].class == BigDecimal

      @name = build_html_name(name)
    end

    @opts[:name] = @name
    @type = @opts.delete(:as) || :text

    send("as_#{@type}")
  end

  # hidden field
  def hidden object, value=nil
    if value
      value = value[:value] if value.is_a?(Hash)
      name = object
    else
      if object.is_a?(Symbol)
        name  = object
        value = @object.send(name)
      elsif object.is_a?(ApplicationModel)
        name  = '%s_id' % object.class.to_s.tableize.singularize

        if @object.respond_to?(name)
          value ||= object.id
        else
          return [
            hidden(:model_id, object.id),
            hidden(:model_type, object.class.name)
          ].join('')
        end
      end
    end

    render name, as: :hidden, value: value
  end

  # Emit the hidden CSRF input matching Lux.current.csrf. Use in raw <form>
  # markup where HtmlForm's auto-injection doesn't apply:
  #
  #   = HtmlInput.csrf
  def self.csrf
    %[<input type="hidden" name="_csrf" value="#{Lux.current.csrf}">]
  end

  private

  def detect_type_from_schema
    return unless db_type = @object.db_schema.dig(@name, :db_type)

    @opts[:as] ||= :datetime if db_type.include?('timestamp')
    @opts[:as] ||= :date     if db_type == 'date'
    @opts[:as] ||= :memo     if db_type == 'text'
    @opts[:as] ||= :checkbox if db_type == 'boolean'
  end

  def apply_schema_rules schema
    rules = schema.rules[@name]
    return unless rules

    @schema = rules

    for k, v in rules[:meta].or({})
      v = @object.instance_exec &v if v.is_a?(Proc)
      @opts[k] = v unless @opts.key?(k)
    end
  end

  # @model.levels_sid -> collection: Models.levels
  def resolve_collection_from_name
    reg = /_s?id$/
    if @name.to_s =~ reg
      lookup = @name.to_s.sub(reg, '')
      if @object.class.respond_to?(lookup)
        @opts[:collection] = @object.class.send(lookup)
      end
    end
  end

  def build_html_name name
    if name.is_a?(Array)
      @field_name = name[0]
      if @object.db_schema[name[0]][:db_type].include?('[]')
        @opts[:value] = name[1].to_s
        @object ? "#{@object.class.to_s.tableize.singularize}[#{name[0]}][]" : "#{name[0]}[]"
      else
        if @object
          @opts[:value] ||= @object.send(name.first.to_sym).dig(*name.drop(1).map(&:to_s))
          name.first.to_s + name.drop(1).map{ "[#{_1}]" }.join('')
        else
          raise 'not implemented'
        end
      end
    elsif @object && name.is_a?(Symbol)
      '%s[%s]' % [@object.class.to_s.tableize.singularize, name]
    end
  end

  def calculate_type
    return :select if @opts[:collection]

    data_type = @object && @object[@name] ? @object[@name].class : String

    if [TrueClass, FalseClass].include?(data_type)
      return :checkbox
    else
      return :string
    end
  end

  def prepare_collection data
    ret = []

    # collection: :kinds -> @object.class.kinds
    data = @object.class.send data if @object && data.is_a?(Symbol)

    if data.is_hash?
      for id, name in data
        name = name[:name] if name.is_hash?
        ret.push [id.to_s, name]
      end
    else
      for el in data
        if el.respond_to?(:select_name)
          ret.push [el.id.to_s, el.select_name]
        elsif el.respond_to?(:name)
          ret.push [el.id.to_s, el.name]
        elsif el.kind_of?(Array)
          ret.push [el[0].to_s, el[1]]
        else
          ret.push [el.to_s, el]
        end
      end
    end

    ret
  end
end
