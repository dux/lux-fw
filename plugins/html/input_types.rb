# frozen_string_literal: true

class HtmlInput

  # if you call .memo which is not existant, it translates to .as_memo with opts_prepare first
  # def method_missing(meth, *args, &block)
  #   opts_prepare *args
  #   send "as_#{meth}"
  # end

  #############################
  # custom fields definitions #
  #############################

  def as_string
    @opts[:type] = 'text'
    @opts[:autocomplete] ||= 'off'
    @opts.tag(:input)
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
    @opts[:value] = @opts[:value].short(true) if @opts[:value].respond_to?(:short)
    @opts.tag(:input)
  end

  def as_datetime
    if @opts[:value].present?
      value = Time.parse(@opts[:value].to_s) rescue Time.now
      @opts[:value] = value.long
    end

    @opts[:type] = 'text'
    @opts.tag(:input)
  end

  def as_file
    @opts[:type] = 'file'
    @opts.tag(:input)
  end

  def as_textarea
    val = @opts.delete(:value) || ''
    val = val.join($/) if val.is_array?
    comp_style = val.split(/\n/).length + val.length/100
    comp_style = 6 if comp_style < 6
    comp_style = 15 if comp_style > 15
    @opts[:style] = "height:#{comp_style*20}px; #{@opts[:style]};"
    @opts[:autocomplete]   = :off
    @opts[:autocorrect]    = :off
    @opts[:autocapitalize] = :off
    @opts[:spellcheck]     = :false
    @opts.tag(:textarea, val)
  end
  alias :as_memo :as_textarea

  def as_checkbox
    id = Lux.current.uid
    hidden = { :name=>@opts.delete(:name), :type=>:hidden, :value=>@opts[:value] ? 1 : 0, :id=>id }
    @opts[:type] = :checkbox
    @opts[:onclick] = "document.getElementById('#{id}').value=this.checked ? 1 : 0; #{@opts[:onclick]}"
    @opts[:checked] = @opts.delete(:value) ? 1 : nil
    @opts.tag(:input)+hidden.tag(:input)
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
    collection = @opts.delete(:collection)

    @opts[:class] ||= 'form-select'

    if nullval = @opts.delete(:null)
      body.push %[<option value="">#{nullval}</option>] if nullval
    end

    for el in prepare_collection(collection)
      body.push(%[<option value="#{el[0]}"#{@opts[:value].to_s == el[0].to_s ? ' selected=""' : nil}>#{el[1]}</option>])
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
    value = @opts[:value]
    @opts[:style] ||= 'width:150px; float: left; margin-right: 10px;'
    as_text + %[<span style="background-color: #{value.or('#fff')}; height:34px; width:150px; display: inline-block;"></span>]
  end

  def as_geo
    @opts[:type] = 'text'
    @opts[:style] = 'width:200px; float:left;'
    ret = @opts.tag(:input)
    ret += %[ <a target="new" href="http://maps.google.com/maps?q=loc:#{@opts[:value]}" style="display:block; margin-top:7px;">&nbsp;Show on map</a>]
  end

  def as_html
    # consider http://prosemirror.net
    %[<s-pell name="#{@opts[:name]}">#{@opts[:value].to_s.to_html}</s-pell>]
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