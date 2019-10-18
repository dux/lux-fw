class HtmlForm
  def initialize object=nil, opts={}
    if !object
      opts[:method] ||= 'get'

    elsif object.is_a?(ApplicationModel)
      opts['data-model'] = object.class.to_s.underscore.singularize
      opts[:action]      = object.id ? object.api_path(:update) : object.api_path(:create)
      @object = object
    else
      object = '/api/' + object unless object[0,1]
      opts[:action] = object
    end

    opts[:method] ||= 'post'
    opts[:id]     ||= 'form-%s' % Lux.current.uid
    opts[:class]  ||= :default

    opts[:action]   = '/api/' + opts[:action] if opts[:action] && opts[:action][0,1] != '/'

    if opts[:action].to_s.start_with?('/api/')
      opts[:onsubmit]   = 'ApiForm.bind(this); return false;'
      opts['data-done'] = opts.delete(:done) || :refresh
    end

    @opts = opts
  end

  # render full form, accepts block
  def render
    data  = []

    # add hidden fields (ending with _id) for new objects
    if @object && !@object.id
      for k, v in @object.attributes
        if v.present?
          data.push hidden(k.to_sym, v)
        end
      end
    end

    data.push yield(self) if block_given?

    data = wrap data.join($/)

    @opts.tag :form, data
  end

  # hidden filed
  def hidden object, value=nil
    value   = value[:value] if value.is_a?(Hash)

    if object.is_a?(ApplicationModel)
      name = '%s_id' % object.class.to_s.tableize.singularize

      if @object.respond_to?(name)
        value ||= @object.send(name)
        hidden_field name, value
      else
        [
          hidden_field(:model_id, object.id),
          hidden_field(:model_type, object.class.name)
        ].join('')
      end
    else
      value ||= @object.send(object) if object.is_a?(Symbol)
      hidden_field object, value
    end
  end

  # standard input linked to HtmlInput class
  def input name, opts={}
    if @object && name.is_a?(Symbol)
      rules = @object.class.typero.rules[name][:meta] || {}

      for k, v in rules.slice(:label, :hint, :as)
        v = @object.instance_exec &v if v.is_a?(Proc)
        opts[k] = v unless opts.key?(k)
      end

      if @object.respond_to?(:db_schema)
        opts[:as] ||= :datetime if @object.db_schema[name][:db_type].include?('timestamp')
        opts[:as] ||= :date     if @object.db_schema[name][:db_type] == 'date'
        opts[:as] ||= :memo     if @object.db_schema[name][:db_type] == 'text'
      end
    end

    opts[:placeholder] ||= 'https://...' if name.to_s.ends_with?('url')

    @name          = name
    opts[:id]    ||= Lux.current.uid
    opts[:value] ||= Lux.current.request.params[name] if @opts[:method] == 'GET'
    input_object   = HtmlInput.new(@object)
    data           = input_object.render(name, opts)
    @type          = input_object.type
    data
  end

  private

  # format input name
  def input_name name
    if @object
      '%s[%s]' % [@object.class.to_s.tableize.singularize, name]
    else
      name.to_s
    end
  end

  # create hidden field
  def hidden_field name, value
    {
      type:  :hidden,
      name:  '__enc__%s' % Lux.current.uid,
      value: Crypt.short_encrypt([name, value])
    }.tag :input
  end
end

###

module MainHelper
  def form location=nil, opts={}, &block
    builder = HtmlForm.new location, opts
    builder.render &block
  end
end

###

Lux.plugin 'api'

class ApplicationApi
  before do
    for key in params.keys
      next unless key.start_with?('__enc__')
      key, value  = Crypt.short_decrypt params.delete(key)
      params[key] = value
    end
  end
end
