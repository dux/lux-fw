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

  def as_hidden
    @opts[:type] = 'hidden'
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
        tags = $.map($('#'+id).val().split(/\s*,\s*/), function(el) {
          val = el.replace(/\s+/,'-');
          return val ? '<span class="label label-default">'+val+'</span> ' : ''
        });
        $('#'+id+'_tags').html(tags)
      }</script>]
    ret += @opts.tag(:input)
    ret += %[<div id="#{@opts[:id]}_tags" style="margin-top:5px;"></div>]
    ret += %[<script>if (window.$) { draw_tag('#{@opts[:id]}'); } else { window.onload = function(){ draw_tag('#{@opts[:id]}'); } }</script>]
    ret
  end

  def as_date
    @opts[:type]         = 'text'
    @opts[:style]        = 'width: 120px; display: inline;'
    @opts[:value]        = @opts[:value].strftime('%d.%m.%Y') rescue @opts[:value]
    @opts[:autocomplete] = :off

    ret = @opts.tag(:input)
    ret += '<span class="date-ago"> &bull; %s</span>' % Time.ago(Time.parse(@opts[:value])) if @opts[:value].present? && !@opts.delete(:no_ago)
    # ret += ' &bull; <small>%s</small>' % @opts[:hint]
    ret + %[<script>new Pikaday({ field: document.getElementById('#{@opts [:id]}'), format: "DD.MM.YYYY" }); </script>]
  end

  def as_datetime
    value = @opts[:value]
    id    = @opts[:id]

    value_day  = value ? value.strftime('%Y-%m-%d') : ''
    value_time = value ? value.strftime('%H:%M') : ''
    value_all  = value ? value.strftime('%H:%M') : ''

    base = { class: 'form-control', onchange: "datetime_set('#{id}');", style: 'width: 160px; display: inline;'  }

    input_day  = base.merge({ type: :date, id: '%s_day' % id, value: value_day }).tag :input
    input_time = base.merge({ style: 'width: 110px; display: inline;', type: :time, id: '%s_time' % id, value: value_time }).tag :input
    input_all  = base.merge({ style: 'width: 150px; display: inline;', type: :text, id: id, name: @opts[:name], onfocus: 'blur();' }).tag :input
    script     = %[<script>window.datetime_set = function(id) { $('#'+id).val($('#'+id+'_day').val()+' '+$('#'+id+'_time').val()); }; datetime_set('#{id}');</script>]
    desc       = value ? '&mdash;' + Time.ago(value) : ''

    [input_day, input_time, input_all, script, desc].join(' ')
  end

  def as_datebuttons
    @opts[:type] = 'text'
    @opts[:style] = 'width:100px; display:inline;'
    @opts[:id] = "date_#{Lux.current.uid}"
    id = "##{@opts[:id]}"
    ret = @opts.tag(:input)
    ret += %[ <button class="btn btn-default btn-sm" onclick="$('#{id}').val('#{DateTime.now.strftime('%Y-%m-%d')}'); return false;">Today</button>]
    for el in [1, 3, 7, 14, 30]
      date = DateTime.now+el.days
      name = el.to_s
      name += " (#{date.strftime('%a')})" if el < 7
      ret += %[ <button class="btn btn-default btn-sm" onclick="$('#{id}').val('#{(DateTime.now+el.days).strftime('%Y-%m-%d')}'); return false;">+#{name}</button>]
    end
    ret
  end

  def as_user
    button_text = if @opts[:value].to_i > 0
      usr = User.find(@opts[:value])
      "#{usr.name} (#{usr.email})"
    else
      'Select user'
    end

    @opts[:style] = "width:auto;#{@opts[:style]};"
    @opts[:onclick] = %[Dialog.render(this,'Select user', '/part/users/single_user?product_id=#{@object.bucket_id}');return false;]
    @opts.tag :button, button_text
  end

  def as_photo
    @opts[:type] = 'hidden'
    if @opts[:value].present?
      img = Photo.find(@opts[:value])
      @image = %[ <img id="#{@opts[:id]}_image" style="height:34px; cursor:pointer;" src="#{img.thumbnail}" onclick="window.open('#{img.image.remote_url}')" /> <span class="btn btn-default btn-xs" onclick="$('##{@opts[:id]}').val('');$('##{@opts[:id]}_image').remove();$(this).remove();">&times;</span>]
    end
    picker = @opts.tag(:input)
    %[<span class="btn btn-default" onclick="Photo.pick('#{@opts[:id]}', function(id) { alert('Chosen: '+id) })">Select photo</span>#{picker}#{@image}]
  end

  def as_photos
    @opts[:type] = 'text'
    @opts[:style] = 'width:150px; display:inline;'
    @opts[:class] += ' mutiple'
    @images = []
    if @opts[:value].present?
      for el in @opts[:value].split(',').uniq
        img = Photo.find(el.to_i) rescue next
        @images.push %[ <img style="height:34px; cursor:pointer;" src="#{img.thumbnail}" onclick="window.open('#{img.image.remote_url}')" />]
      end
    end
    picker = @opts.tag(:input)
    %[<span class="btn btn-default" onclick="Photo.pick('#{@opts[:id]}', function(id) { alert('Chosen: '+id) })">Add photo</span> #{picker}<div class="images" style="padding-top:5px;">#{@images.join(' ')}</div>]
  end

  def as_admin_password
    @opts[:type] = 'text'
    @opts[:style] = 'display:none;'
    @opts[:value] = ''
    ret = @opts.tag(:input)
    %[<span class="btn btn-default" onclick="$(this).hide();$('##{@opts[:id]}').show().val('').attr('type','password').focus()">Set pass</span> #{ret}]
  end

  def as_color
    value = @opts[:value]
    @opts[:style] ||= 'width:150px; float: left; margin-right: 10px;'
    as_text + %[<span style="background-color: #{value.or('#fff')}; height:34px; width:150px; display: inline-block;"></span>]
  end

  def as_array_values
    name = @opts[:name]
    ret = []
    values = @opts[:value].kind_of?(String) ? @opts[:value].split(',') : @opts[:value]
    for el in @opts[:collection]
      ret.push %[<label style="position:relative; top:4px;">
          <input name="#{name}[#{el[1]}]" value="1" type="checkbox" #{values[el[1]].present? ? 'checked=""' : ''} style="position:relative;top:2px; left:2px;" />
          <span style="margin-right:10px;">#{el[0]}</span>
        </label>]
    end
    ret.join('')
  end

  def as_pass
    value = @opts[:value]
    id = @opts[:id]
    @opts[:value] = ''
    @opts[:style] = 'width:200px; display:inline;'
    ret = @opts.tag(:input)
    %[<span class="btn btn-default" onclick="$(this).hide(); $(this).next().show().focus();">#{value.present? ? 'Change' : 'Set'} password</span><span id="s-#{id}" style="display:none;">#{ret} or <a onclick="p=$(this).parent(); p.hide(); p.prev().show(); return false;" href="#">cancel</a></span>]
  end

  def as_image
    @opts[:type]           = 'text'
    @opts[:style]          = 'width:350px; float:left;'
    @opts[:autocomplete] ||= 'off'

    input     = @opts.tag(:input)
    path_name = 'image_upload_dialog'
    input    += %[<span class="btn btn-default" style="float:left; margin-left:5px;" onclick="Dialog.template('#{path_name}', function(url){ $('##{@opts[:id]}').val(url); Dialog.close(); })">upload</span>]

    if @opts[:value].present?
      input = %[<img onload="i = new Image(); i.src='#{@opts[:value]}'; $('#img_size_#{@opts[:id]}').html(i.width+' x '+i.height)" src="#{@opts[:value]}" onclick="window.open('#{@opts[:value]}')" style="width:100px; border:1px solid #ccc; float:left; margin-right:10px;" /> #{input}]
      input += %[<br /><br /><span id="img_size_#{@opts[:id]}">...</span>]
    end

    '<span style="clear: both; display: block;"></span>' + input
  end

  def as_geo
    @opts[:type] = 'text'
    @opts[:style] = 'width:200px; float:left;'
    ret = @opts.tag(:input)
    ret += %[ <a target="new" href="http://maps.google.com/maps?q=loc:#{@opts[:value]}" style="display:block; margin-top:7px;">&nbsp;Show on map</a>]
  end

  def as_html_trix
    %[
      <div class="hide-for-popup" style="width: 100%;">
        <textarea id="trix_#{@name}" name="#{@opts[:name]}" style="display:none;">#{@opts[:value]}</textarea>
        <trix-editor input="trix_#{@name}"></trix-editor>
      </div>
    ]
  end

  def as_button_select
    body = ['<div class="btn-group">']
    collection = @opts.delete(:collection)
    for el in prepare_collection(collection)
      opts = { class:'btn btn-sm' }
      ap "#{@opts[:name]} - #{@opts[:value]} == #{el[0]}"
      opts[:class] += ' btn-primary' if @opts[:value].to_s == el[0].to_s
      opts[:onclick] = "$(this).parent().find('.btn').removeClass('btn-primary'); $(this).addClass('btn-primary').blur(); $(this).addClass('btn-primary').blur();"
      opts[:onclick] += @opts[:onclick] ? "(#{@opts[:onclick].sub(/;\s*$/,'')})('#{el[0]}')" : "$('##{@opts[:id]}').val('#{el[0]}')"
      opts[:onclick] += '; return false;'
      body.push opts.tag(:button, el[1])
    end
    body.push '</div>'
    body.push @opts.pluck(:name, :id, :value).merge(type: :hidden).tag(:input)
    body.join('')
  end

  def as_address
    val = @opts[:value]
    @opts[:style] ||= 'height:55px; width:250px; float: left; margin-right:5px;'
    ret = as_textarea
    ret += %[<div><a class="btn btn-default btn-xs" onclick="window.open('https://www.google.hr/maps?q='+$('##{@opts[:id]}').val()); return false;">open in new window</a></div>] if val.to_s.length > 5
    ret
  end

  def as_images
    path_name = defined?(Storage) ? :storages : :images

    val = @opts[:value].to_s
    ret = as_memo
    ret += '<div style="margin-top: 7px;"></div>'
    ret += val.split("\n").map{ |url| %[<a href="#{url}" target="_new"><img src="#{url}" style="height:50px; margin-right:5px; border:1px solid #ccc;" /></a>] }.join(' ')
    ret += %[<span class="btn btn-default" style="float:left; margin-left:5px;" onclick='Dialog.template("#{path_name}/select", function(url){ $("##{@opts[:id]}")[0].value += "\\n"+url; Dialog.close(); })'>add image</span>]
   ret
  end

  def as_disabled
    @opts[:disabled] = true
    @opts.delete(:name)
    as_text
  end

end