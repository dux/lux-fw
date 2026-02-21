# frozen_string_literal: true

class HtmlInput

  def as_string
    @opts[:type] = 'text'
    @opts[:autocomplete] ||= 'off'
    @opts[:style] ||= 'width: 100%;'

    prefix = @opts.delete(:prefix)
    out = @opts.tag(:input)
    if prefix
      %[<table style="width: 100%;"><tr>
          <td style="background: #eee; color: #888; border: 1px solid #ddd; border-right: none; padding: 8px 10px 0 10px; width: 20px;">#{prefix}</td>
          <td>#{out}</td>
        </tr></table>]
    else
      out
    end

    if @opts[:focus]
      out += <<~TEXT
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
        n.span(class: 'btn xs danger', onclick: "document.getElementById('#{@opts[:id]}').value=''") { '&times;' }
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

    App.tag 's-input-textarea', {
      name: @opts[:name],
      id: @opts[:id],
      value: val,
      class: @opts[:class],
      style: @opts[:style],
      max: @opts[:max],
      wrap: @opts[:wrap],
      placeholder: @opts[:placeholder],
    }
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
        checked: @object && Array(@object.send(@filed_name)).include?(value) ? 'true' : nil
      }.compact.tag(:input)
    else
      id = Lux.current.uid
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

  def as_checkboxes
    body = []
    collection = @opts.delete(:collection)

    @opts[:type] = :checkbox

    null  = @opts.delete(:null)
    value = @opts.delete(:value).to_s

    body.push %[<label>#{opts.tag(:input)} #{null}</label>] if null

    prepare_collection(collection).each do |el|
      opts = @opts.dup
      opts[:value]   = el[0]
      opts[:checked] = true if value == el[0].to_s

      body.push %[<label>#{opts.tag(:input)} #{el[1]}</label>]
    end

    '<div class="form-checkboxes">%s</div>' % body.join("\n")
  end

  def as_select
    body = []

    @opts[:class] ||= 'form-select'

    if nullval = @opts.delete(:null)
      body.push %[<option value="">#{nullval}</option>] if nullval
    end

    collection = @opts.delete(:collection)

    for value, name in prepare_collection(collection)
      opts            = {}
      opts[:value]    = value || ''
      opts[:selected] = 'true' if @opts[:value].to_s == value.to_s
      body.push opts.tag(:option, name)
    end

    body = body.join("\n")
    @opts.tag(:select, body)
  end

  def as_radio
    return as_radios if @opts[:collection]

    @opts[:type] = :radio
    @opts[:checked] = @opts[:value] == @object.send(@name) ? true : nil
    @opts.tag(:input)
  end

  def as_radios
    body = []
    collection = @opts.delete(:collection)

    @opts[:type] = :radio

    null  = @opts.delete(:null)
    value = @opts.delete(:value).to_s

    body.push %[<label>#{opts.tag(:input)} #{null}</label>] if null

    prepare_collection(collection).each do |el|
      opts = @opts.dup
      opts[:value]   = el[0]
      opts[:checked] = true if value == el[0].to_s

      body.push %[<label>#{opts.tag(:input)} #{el[1]}</label>]
    end

    '<div class="form-radios">%s</div>' % body.join("\n")
  end

  def as_tag
    @opts[:value] = @opts[:value].or([]).join(', ') if ['Array', 'Sequel::Postgres::PGArray'].index(@opts[:value].class.name)
    @opts[:id] ||= Lux.current.uid
    @opts[:type] = :text
    @opts[:onkeyup] = %[draw_tag('#{@opts[:id]}')]
    @opts[:autocomplete] ||= 'off'
    @opts[:style] = ['display: block; width: 100%;', @opts[:style]].join(';')

    ret = %[
    <script>
       window.draw_tag = window.draw_tag || function (id) {
        tags = $.map(String($('#'+id).val()).split(/\s*,\s*/), function(el) {
          val = el.replace(/\s+/,'-');
          return val ? '<span class="label label-primary">'+val+'</span> ' : ''
        });
        $('#'+id+'_tags').html(tags)
      }</script>]
    ret += @opts.tag(:input)
    ret += %[<div id="#{@opts[:id]}_tags" style="margin-top:5px;"></div>]
    ret += %[<script>if (window.$) { draw_tag('#{@opts[:id]}'); } else { window.onload = function(){ draw_tag('#{@opts[:id]}'); } }</script>]
    ret
  end

  def as_color
    c1 = {}
    c1[:id]       = @opts[:id]+'1'
    c1[:type]     = :color
    c1[:style]    = 'height: 44px; position: relative; top: 11px; margin-right: 10px;'
    c1[:onchange] = "$('##{@opts[:id]}2').val(this.value).css('background-color', this.value)"
    c1[:value]    = @opts[:value].or @opts[:placeholder] || '#ffffff'
    c1[:disabled] = true if @opts[:disabled]

    c2 = {}
    c2[:id]          = @opts[:id]+'2'
    c2[:type]        = :text
    c2[:name]        = @opts[:name]
    c2[:value]       = @opts[:value]
    c2[:style]       = "background-color:#{@opts[:value]}; width: 90px;"
    c2[:onkeyup]     = "if (this.value && this.value.length==7) { $('##{@opts[:id]}1').val(this.value); $(this).css('background-color', this.value) }"
    c2[:placeholder] = @opts[:placeholder]
    c2[:disabled]    = true if @opts[:disabled]

    tag.div style: 'position: relative; top: -12px;' do |n|
      n.push c1.tag(:input)
      n.push c2.tag(:input)

      if @opts[:value] && !@opts[:disabled]
        n.push %[ &sdot; <span class="btn btn-xs" onclick="$('##{c2[:id]}').val('')">clear</span>]
      end
    end
  end

  def as_geo
    @opts[:type] = 'text'
    if @opts[:value]
      @opts[:style] = 'width:200px; float:left; margin-right: 20px;'
      @opts[:value] = @opts[:value].map(&:to_f).join(', ')
      ret = @opts.tag(:input)
      ret += %[ <a target="new" href="http://maps.google.com/maps?q=loc:#{@opts[:value]}" style="display:block; margin-top:7px;">&nbsp;Show on map</a>]
    else
      @opts.tag(:input)
    end
  end

  def as_address
    val = @opts[:value]
    @opts[:style] ||= 'height:55px; width:250px; float: left; margin-right:5px;'
    ret = as_textarea
    ret += %[<div><a class="btn btn-default btn-xs" onclick="window.open('https://www.google.hr/maps?q='+$('##{@opts[:id]}').val()); return false;">open in new window</a></div>] if val.to_s.length > 5
    ret
  end

  def as_disabled
    @opts[:disabled] = true
    @opts.delete(:name)
    as_text
  end
end
