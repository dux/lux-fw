# input = HtmlInput.new(User.first)
# input.render :email, value: 'foo@bar.baz'

class HtmlInput
  attr_accessor :type, :opts

  def initialize object=nil, opts={}
    if object.is_a?(Hash)
      opts   = object
      object = nil
    end

    @object = object
    @opts   = opts

    @opts.delete :disabled if @opts[:disabled].to_s == 'false'
  end

  def tag *args, &block
    HtmlTag *args, &block
  end

  # .render :name          # @object.name
  # .render settings: :key # @object.settings[key]
  def render name, opts = {}
    @opts.merge! opts
    @name = name

    @opts[:placeholder] ||= 'email...' if @name.to_s.include?('email')
    @opts[:placeholder] ||= 'https://...' if @name.to_s.end_with?('url')
    @opts[:id]          ||= 'i_%s' % Lux.current.uid

    if @object && @object.class.respond_to?(:schema) && [Symbol, Array].include?(@name.class)
      schema = @object.class.schema || raise('Typero schema for object "%s" not found' % @object.class)

      if db_type = @object.db_schema.dig(@name, :db_type)
        @opts[:as] ||= :datetime if db_type.include?('timestamp')
        @opts[:as] ||= :date     if db_type == 'date'
        @opts[:as] ||= :memo     if db_type == 'text'
        @opts[:as] ||= :checkbox if db_type == 'boolean'
      end

      if rules = schema.rules[@name]
        for k, v in rules[:meta].or({})
          v = @object.instance_exec &v if v.is_a?(Proc)
          @opts[k] = v unless @opts.key?(k)
        end
      end

      if @name.is_a?(Symbol) && @object.respond_to?(:db_schema) && !@opts[:as]
        # @model.levels_sid -> collection: Models.levels
        reg = /_s?id$/
        if @name.to_s =~ reg
          @name = @name.to_s.sub(reg, '')
          if @object.class.respond_to?(@name)
            @opts[:collection] = @object.class.send(@name)
          end
        end
      end

      # default value for as
      @opts[:as]    ||= calculate_type
      @opts[:id]    ||= Lux.current.uid
      @opts[:value] ||= @object.send(@name) if @object && @name.is_a?(Symbol)
      @opts[:value]   = @opts[:default] if @opts[:value].blank?

      # convert decimal numbers to float
      @opts[:value] = @opts[:value].to_f if @opts[:value].class == BigDecimal

      @name = if name.is_a?(Array)
        @filed_name = name[0]
        if @object.db_schema[name[0]][:db_type].include?('[]')
          @opts[:value] = name[1].to_s
          @object ? "#{@object.class.to_s.tableize.singularize}[#{name[0]}][]" : "#{name[0]}[]"
        else
          # [:opts, :app, :posts] => model[opts][app][posts]
          if @object
            @opts[:value] ||= @object.send(name.first.to_sym).dig(*name.drop(1).map(&:to_s))
            name.first.to_s + name.drop(1).map{ "[#{_1}]" }.join('')
          else
            raise 'not implemented'
          end
        end
      elsif @object && name.class == Symbol
        '%s[%s]' % [@object.class.to_s.tableize.singularize, name]
      end
    end

    @opts[:name] = @name
    @type = @opts.delete(:as) || :text

    send("as_#{@type}")
  end

  # hidden filed
  def hidden object, value=nil
    if value
      value = value[:value] if value.is_a?(Hash)
      name = object
    else
      if object.is_a?(Symbol)
        # .hidden :user_id -> .hidden :user_id, @object.send(:user_id_
        name  = object
        value = @object.send(name)
      elsif object.is_a?(ApplicationModel)
        # .hidden @user -> .hidden :user_id, @user.id
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

  private

  # figure out default type (:as) for input elements
  def calculate_type
    return :select if @opts[:collection]

    data_type = @object && @object[@name] ? @object[@name].class : String

    if [TrueClass, FalseClass].include?(data_type)
      return :checkbox
    else
      return :string
    end
  end

  # prepare collection for radios and selects
  def prepare_collection data
    ret = []

    # collection: :kinds -> @object.class.kinds
    data = @object.class.send data if @object && data.is_a?(Symbol)

    if data.is_hash?
      # { id: {name:'Foo'} } : { id: 'Foo' }
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
        elsif data.is_hash?
          ret.push el
        else
          ret.push [el.to_s, el]
        end
      end
    end

    ret
  end
end
