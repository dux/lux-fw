class HtmlForm
  def row name = nil, opts = {}
    if block_given?
      label = (name || Lux::SafeString.new('&nbsp;')).tag(:label)
      (label + Lux::SafeString.new(yield.to_s)).tag(:div, class: 'form-row')
    else
      return hidden name, opts[:value] if opts[:as] == :hidden
      r = row_prepare(name, opts)

      label = r[:label].to_s.tag(:label, for: opts[:id])
      hint  = opts[:hint] ? opts[:hint].to_s.tag(:small, class: 'gray', style: 'display:block;') : ''
      info  = opts[:info] ? opts[:info].to_s.tag(:div, class: 'mb-2 small') : ''

      if opts[:flag]
        locale = Lux.current.locale
        style = opts[:flag] == true ? '' : opts[:flag]
        if style.length == 2
          locale = style
          style = ''
        end
        label += { class: 'input', locale: locale, size: 20, style: style }.tag(:'ui-flag')
      end

      Lux::SafeString.join([label, info, r[:node], hint]).tag(:div, class: "form-row as-#{@type}")
    end
  end

  private

  def row_prepare name, opts
    if @object && (@object.class.data[name] rescue nil)
      name = [:data, name]
    end

    opts[:value]    = Lux.current.request.params[name] if !@object && opts[:value].nil?
    opts[:onchange] = "Fez.load('?'+$(this.form).serialize())" if opts.delete(:autosubmit)

    node  = input(name, opts)
    label = opts[:label]
    # humanize operation_ref → "Operation ref"; strip trailing id/sid/ref suffixes
    label ||= (name.is_a?(Array) ? name[1] : name).to_s.humanize.sub(/\s(s?id|ref)$/i, '')

    { node: node, label: label }
  end

  public

  def submit name = nil, opts = {}, &block
    if name.is_a?(Hash)
      opts = name
      name = nil
    end

    action_name = @object.try(:id) ? 'update' : 'create'

    if disabled = @opts[:disabled]
      disabled = 'You are not allowed to %s' if disabled.class == TrueClass
      name = disabled
    end

    name ||= '%s ' + (@object ? @object.class.display_name : 'null')
    name   = name % action_name if name.include?('%s')

    opts           = { data:" #{opts}" } if opts.kind_of?(String)
    opts[:type]    = :submit
    opts[:class] ||= 'btn btn-primary'
    opts[:style] ||= 'padding-left: 10px'
    opts[:'data-key'] ||= 'ctrl+s'

    opts[:icon] ||= @object&.id ? :floppy_disk : :plus
    name = { name: opts[:icon] }.tag(:'ui-icon') + ' ' + name

    data  = opts.tag(:button, name)
    data += opts[:data] if opts[:data]
    # SafeString#+ escapes plain text, so a plain ' ' + markup would lose the markup
    data += Lux::SafeString.new(" #{block.call}") if block
    data += Lux::SafeString.join([' or ', 'cancel'.tag(:a, class: 'btn btn-sm', href: opts[:cancel])]) if opts[:cancel]
    data += Lux::SafeString.join([' or ', 'go back'.tag(:a, class: 'btn btn-sm', href: opts[:back])]) if opts[:back]

    if @object && (path = opts[:delete])
      data = Lux::SafeString.new <<~TEXT
      <div class="flex">
        <div class="flex-1">#{data}</div>
        <div class="flex-1 text-right">
          <span
            class="btn btn-danger btn-xs"
            onclick='Dialog.inlineConfirm(this, "Delete #{@object.class.to_s.humanize.downcase} ?", { yes: "Delete!", cancel: "cancel", callback: function() { #{Api(@object.api_path(:destroy)).refresh(path)} }})'
          >delete</span>
        </div>
      </div>
      TEXT
    end

    Lux::SafeString.new <<~TEXT
      <div class="form-row form-submit"><label>#{opts[:narrow] ? '' : '&nbsp;'}</label>#{data}</div>
    TEXT
  end

  def isubmit name
    HtmlTag.button(name, class: 'btn btn-lg', style: 'height: 42px; margin-left: 2px; margin-top: -3px;')
  end

  def button name, opts = {}
    value = @object ? @object.send(name) : Lux.current.request.params[name]

    opts[:name]    = name
    opts[:class]   = 'btn'
    opts[:class]  += ' btn-primary' if value == opts[:value].to_s
    opts[:label] ||= opts[:value].to_s.humanize

    opts.tag :button, opts.delete(:label)
  end

  def fieldset title = nil, desc = nil
    legend  = Lux::SafeString.join([title.to_s])
    legend += desc.to_s.tag(:div, class: 'gray small', style: 'padding-top: 10px;') if desc
    attrs   = title ? {} : { style: 'border-top: none;' }
    (legend.tag(:legend) + Lux::SafeString.new(yield.to_s)).tag(:fieldset, **attrs)
  end

  def done
    @opts[:done] = yield.gsub($/, '; ').gsub(/\s+/, ' ')
  end
end

###

# HtmlHelper, not ApplicationHelper: the app's own helpers must win
module HtmlHelper
  def form obj, opts = {}, &block
    begin
      builder = HtmlForm.new obj, opts
      builder.render &block
    rescue Lux::Policy::Error => e
      msg = e.message.split(' - ')[0]
      return msg.tag 'ui-info', type: :error
    end
  end

  def input name, opts = {}
    opts[:name] = name
    HtmlInput.new.render name, opts
  end
end
