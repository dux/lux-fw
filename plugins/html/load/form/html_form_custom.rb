class HtmlForm
  def row name = nil, opts = {}
    if block_given?
      %[<div class="form-row"><label>#{name || '&nbsp;'}</label>#{yield}</div>]
    else
      return hidden name, opts[:value] if opts[:as] == :hidden
      r = row_prepare(name, opts)

      label = %[<label for="#{opts[:id]}">#{r[:label]}</label>]
      hint  = opts[:hint] ? %[<small class="gray" style="display:block;">#{opts[:hint]}</small>] : ''
      info  = opts[:info] ? %[<div class="mb-2 small">#{opts[:info]}</div>] : ''

      if opts[:flag]
        locale = Lux.current.locale
        style = opts[:flag] == true ? '' : opts[:flag]
        if style.length == 2
          locale = style
          style = ''
        end
        label += %[<ui-flag class="input" locale="#{locale}" size="20" style="#{style}"></ui-flag>]
      end

      %[<div class="form-row as-#{@type}">#{label}#{info}#{r[:node]}#{hint}</div>]
    end
  end

  private

  def row_prepare name, opts
    if @object && (@object.class.data[name] rescue nil)
      name = [:data, name]
    end

    opts[:value]    = Lux.current.request.params[name] if !@object && opts[:value].nil?
    opts[:onchange] = "Pjax.load('?'+$(this.form).serialize())" if opts.delete(:autosubmit)

    node  = input(name, opts)
    label = opts[:label]
    label ||= (name.is_a?(Array) ? name[1] : name).to_s.humanize.sub(/\ss?id$/, '')

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

    opts[:icon] ||= @object&.id ? :floppy_disk : :plus
    name = '<ui-icon name="%s"></ui-icon> %s' % [opts[:icon], name]

    data  = opts.tag(:button, name)
    data += opts[:data] if opts[:data]
    data += ' ' + block.call if block
    data += %[ or <a class="btn btn-sm" href="#{opts[:cancel]}">cancel</a>] if opts[:cancel]
    data += %[ or <a class="btn btn-sm" href="#{opts[:back]}">go back</a>] if opts[:back]

    if @object && (path = opts[:delete])
      data = <<~TEXT
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

    <<~TEXT
      <div class="form-row form-submit"><label>#{opts[:narrow] ? '' : '&nbsp;'}</label>#{data}</div>
    TEXT
  end

  def isubmit name
    HtmlTag.button(class: 'btn btn-lg', style: 'height: 42px; margin-left: 2px; margin-top: -3px;') do |n|
      n.push name
    end
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
    style = title ? '' : ' style="border-top: none;"'
    title += %[<div class="gray small" style="padding-top: 10px;">#{desc}</div>] if desc
    %[<fieldset#{style}><legend>#{title}</legend>#{yield}</fieldset>]
  end

  def done
    @opts['data-done'] = yield.gsub($/, '; ').gsub(/\s+/, ' ')
  end
end

###

module ApplicationHelper
  def form obj, opts = {}, &block
    begin
      builder = HtmlForm.new obj, opts
      builder.render &block
    rescue Policy::Error => e
      msg = e.message.split(' - ')[0]
      return msg.tag 'ui-info', { type: :error }
    end
  end

  def input name, opts = {}
    opts[:name] = name
    HtmlInput.new.render name, opts
  end
end
