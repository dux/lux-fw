class HtmlForm
  attr_reader :object, :opts

  def initialize object = nil, opts = {}
    if object.is_a?(Hash)
      opts   = object
      object = nil
    elsif object.is_a?(String)
      opts[:action] = object
      object = nil
    end

    @object = object
    @opts   = opts

    @opts[:method] ||= 'post'
    @opts[:id]     ||= 'form-%s' % Lux.current.uid

    setup_object if @object

    # /api/ forms render as <api-form>, which posts over XHR and runs done:
    @api = @opts[:action].to_s.start_with?('/api/')
    @opts[:done] ||= :refresh if @api
    @opts.delete(:plain) unless @opts[:plain]
  end

  def push data
    @data ||= []
    @data.push data
  end

  def input name, opts = {}
    node = HtmlInput.new(@object, opts.dup)
    data = node.render name
    @type = node.type
    node.opts.each { |key, value| opts[key] = value unless opts.key?(key) }
    data
  end

  def hidden *args
    HtmlInput.new(@object).hidden *args
  end

  def row name = nil, opts = {}
    return super if block_given?
    return hidden name, opts[:value] if opts[:as] == :hidden
    r = row_prepare(name, opts)

    label = r[:label].upcase.tag(:label, for: opts[:id])
    hint  = opts[:hint] ? opts[:hint].tag(:span, class: 'gray text-sm', style: 'display:block;') : ''
    info  = opts[:info] ? opts[:info].tag(:div, class: 'mb-2 text-sm') : ''

    if opts[:flag]
      locale = Lux.current.locale
      style = opts[:flag] == true ? '' : opts[:flag]
      if style.length == 2
        locale = style
        style = ''
      end
      label += { class: 'input', locale: locale, size: 20, style: style }.tag(:'ui-flag')
    end

    if @type.to_s == 'checkbox'
      r[:node].tag(:div, class: "form-row as-#{@type}")
    else
      Lux::SafeString.join([label, info, r[:node], hint]).tag(:div, class: "form-row as-#{@type}")
    end
  end

  def render
    data = []

    # a block is template output (escaped where it printed text); pushed data is markup
    yielded = Lux::SafeString.new(block_given? ? yield(self).to_s : (@data || []).join($/))

    if @object && !@object.id
      for k, v in @object.attributes
        data.push hidden(k.to_sym, v) if v.present?
      end
    end

    # Auto-inject CSRF token for state-changing forms; harmless on Bearer-auth
    # endpoints (server skips the check) but essential for cookie-session POSTs.
    if @opts[:method].to_s.downcase != 'get'
      data.push HtmlInput.csrf
    end

    data.push yielded
    data = Lux::SafeString.join(data, $/)

    @opts[:enctype] ||= 'multipart/form-data' if yielded.include?('file') && @opts[:method] != 'get'

    if @opts.delete(:disabled)
      data = data.tag(:fieldset, disabled: true, style: 'margin:0; padding: 0;')
    end

    @opts.tag(@api ? :'api-form' : :form, data)
  end

  private

  def setup_object
    @opts[:model] = @object.class.to_s.underscore.singularize

    if @object.ref
      @opts[:action] = @object.api_path(:update)
      @object.can.update!
    else
      @opts[:action] = @object.api_path(:create)
      @object.can.create!
    end

    @opts[:action] = '/api/' + @opts[:action] if @opts[:action] && @opts[:action][0,1] != '/'
  end
end
