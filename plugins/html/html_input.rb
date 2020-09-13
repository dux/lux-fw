# input = HtmlInput.new(User.first)
# input.render :email, value: 'foo@bar.baz'

class HtmlInput
  attr_accessor :type

  def initialize object=nil, opts={}
    if object.is_a?(Hash)
      opts   = object
      object = nil
    end

    @object = object
    @opts   = opts.dup
  end

  def tag
    HtmlTagBuilder
  end

  # .render :name          # @object.name
  # .render settings: :key # @object.settings[key]
  def render name, opts={}
    @opts.merge! opts

    @name =
    if name.is_a?(Array)
      @opts[:value] = (@object.send(name.first) || {})[name[1].to_s] if @object
      @opts[:name]  = '%s[%s]' % name
    else
      @opts[:name] = name
    end

    opts_prepare

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
          value ||= @object.send(name)
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

  # exports @name and @opts globals
  def opts_prepare
    # default value for as
    @opts[:as]    ||= calculate_type
    @opts[:id]    ||= Lux.current.uid
    @opts[:value] ||= @object.send(@name) if @object && @name.is_a?(Symbol)
    @opts[:value]   = @opts[:default] if @opts[:value].blank?

    @opts[:name] = @object ? '%s[%s]' % [@object.class.name.underscore, @name] : @name

    # convert decimal numbers to float
    @opts[:value] = @opts[:value].to_f if @opts[:value].class == BigDecimal
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
        if data[0].respond_to?(:select_name)
          ret.push [el.id.to_s, el.select_name]
        elsif data[0].respond_to?(:name)
          ret.push [el.id.to_s, el.name]
        elsif data[0].kind_of?(Array)
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
