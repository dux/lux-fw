# frozen_string_literal: true

class HtmlInput
  def as_string
    @opts[:type] = 'text'
    @opts[:autocomplete] ||= 'off'
    @opts[:style] ||= 'width: 100%;'

    prefix = @opts.delete(:prefix)
    out = @opts.tag(:input)
    out =
    if prefix
      Lux::SafeString.new %[<table style="width: 100%;"><tr>
          <td style="background: #eee; color: #888; border: 1px solid #ddd; border-right: none; padding: 8px 10px 0 10px; width: 20px;">#{escape_text prefix}</td>
          <td>#{out}</td>
        </tr></table>]
    else
      out
    end

    if @opts[:focus]
      out += Lux::SafeString.new <<~TEXT
        <script>
          setTimeout(()=>{
            const el = document.getElementById('#{@opts[:id]}')
            if (el) { el.focus() }
          }, 100)
        </script>
      TEXT
    end

    out
  end
  alias :as_text :as_string

  def as_password
    @opts[:type] = 'password'
    @opts.tag(:input)
  end

  def as_email
    @opts[:type] = 'email'
    @opts.tag(:input)
  end

  def as_hidden
    @opts[:type] = 'hidden'
    @opts.tag(:input)
  end

  def as_date
    @opts[:type]  = 'date'

    if @opts[:value].respond_to?(:short)
      @opts[:value] = @opts[:value].short(true)
    end

    tag.div do |n|
      @opts[:style] = 'width: 160px;'

      n.push @opts.tag(:input)

      if @opts[:value]
        n.push ' &sdot; '
        n.span(class: 'btn xs danger', onclick: "document.getElementById('#{@opts[:id]}').value=''") { Lux::SafeString.new('&times;') }
      end
    end
  end

  def as_datetime
    if @opts[:value].respond_to?(:long)
      value = Time.parse(@opts[:value].to_s) rescue nil
      @opts[:value] = value ? value.long : nil
    end

    if @opts[:value]
      @opts[:value] = Time.parse(@opts[:value]).xmlschema.split(':').first(2).join(':')
    end

    @opts[:class] ||= 'form-control'

    # use 1 not to show seconds
    @opts[:step]  ||= 60

    @opts[:type] = 'datetime-local'

    @opts[:style] = 'font-size: 18px; height: 44px;'
    @opts.tag(:input)
  end

  def as_file
    @opts[:type] = 'file'
    @opts.tag(:input)
  end

  def as_textarea
    val = @opts.delete(:value) || ''
    val = val.join($/) if val.is_array?

    {
      name: @opts[:name],
      id: @opts[:id],
      value: val,
      class: @opts[:class],
      style: @opts[:style],
      max: @opts[:max],
      wrap: @opts[:wrap],
      placeholder: @opts[:placeholder],
    }.tag('input-textarea')
  end

  def as_memo
    @opts[:wrap] = 'wrap'
    as_textarea
  end

  def as_checkbox
    if @name.end_with?('[]')
      value = @opts[:value].to_s
      {
        id: @opts[:id],
        name: @opts.delete(:name),
        type: :checkbox,
        value: value,
        checked: @object && Array(@object.send(@field_name)).include?(value) ? 'true' : nil
      }.tag(:input)
    else
      id = Lux.ctx.uid
      @opts.delete(:value) if ['0', 'false', 'off'].include?(@opts[:value].to_s)
      # let this be 1 or 0, fix other code if problems
      hidden = {
        name: @opts.delete(:name),
        type: :hidden,
        value: @opts[:value] ? 1 : 0,
        id: id
      }
      @opts[:type] = :checkbox
      @opts[:onclick] = "document.getElementById('#{id}').value=this.checked ? 1 : 0; #{@opts[:onclick]}"
      @opts[:checked] = 'true' if @opts.delete(:value).is_true?
      @opts.tag(:input) + hidden.tag(:input)
    end
  end

  # array column -> one checkbox per collection item, posted as name[]
  def as_checkboxes
    body = []
    collection = @opts.delete(:collection)

    @opts[:type] = :checkbox
    @opts[:name] = "#{@opts[:name]}[]" unless @opts[:name].to_s.end_with?('[]')

    null   = @opts.delete(:null)
    values = Array(@opts.delete(:value)).map(&:to_s)
    attrs  = @opts.except(:id, :label, :hint, :was)

    # blank keeps the field in the post when every box is unchecked; the schema drops blank elements
    body.push({ type: :hidden, name: @opts[:name], value: '' }.tag(:input))
    body.push label_for(attrs.merge(value: '').tag(:input), null) if null

    prepare_collection(collection).each do |el|
      opts = attrs.merge(value: el[0])
      opts[:checked] = true if values.include?(el[0].to_s)

      body.push label_for(opts.tag(:input), el[1])
    end

    Lux::SafeString.join(body, "\n").tag(:div, class: 'form-checkboxes')
  end

  def as_select
    body = []

    @opts[:class] ||= 'form-select'

    if nullval = @opts.delete(:null)
      body.push({ value: '' }.tag(:option, nullval))
    end

    collection = @opts.delete(:collection)

    for value, name in prepare_collection(collection)
      opts            = {}
      opts[:value]    = value || ''
      opts[:selected] = 'true' if @opts[:value].to_s == value.to_s
      body.push opts.tag(:option, name)
    end

    @opts.tag(:select, Lux::SafeString.join(body, "\n"))
  end

  private

  # markup (html_safe?) as is, anything else as escaped text
  def escape_text text
    text.to_s.html_safe? ? text.to_s : text.to_s.html_escape
  end

  # <label><input> text</label>
  def label_for input, text
    Lux::SafeString.new("#{input} #{escape_text text}").tag(:label)
  end
end
