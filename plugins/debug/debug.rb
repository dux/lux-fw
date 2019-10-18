# in layout view add "debug_toggle"
# adds button to view all render sources + root controller

class Lux::View
  def self.wrap_with_debug_info files, data
    return data unless Lux.current.request.params[:debug] == 'render'

    files = [files] unless files.is_a?(Array)
    files = files.compact.map do |file|
      %[<a href="subl://open?url=file:/%s" style="color: #fff;" onmousedown="setTimeout(function() { $('#debug-toggle').click() }, 300)">%s</a>] % [Url.escape(Lux.root.join(file).to_s), file]
    end.join(' &bull; ')

    %[<div style="margin: 10px; border: 1px solid #800;">
      <span style="background-color: #800; color: #fff; padding: 3px; font-size:14px; position: relative; top: -3px;">#{files}</span>
      <br />
      #{data}
    </div>]
  end
end

# HTML helpers
module ApplicationHelper
  def debug_toggle
    button =
    if params[:debug] == 'render'
      {
        id: 'debug-toggle',
        class: 'direct btn btn-xs btn-primary',
        href: Url.qs(:debug, nil)
      }.tag(:a, '-')
    else
      {
        id: 'debug-toggle',
        class: 'direct btn btn-xs',
        href: Url.qs(:debug, :render),
      }.tag(:a, '+')
    end

    out = %[
      <script>$.keyPress('KeyD', function(){ $('#debug-toggle').click() })</script>
      <div style="position: fixed; right: 6px; top: 5px; text-align: right; z-index: 100;">#{button}</div>
    ]
  end

  def files_in_use
    return unless Lux.config(:compile_assets)

    files = Lux.current.files_in_use.map do |file|
      if file[0,1] == '/'
        nil
      else
        file = Lux.root.join(file).to_s
        name = file.split(Lux.root.to_s+'/').last.sub(%r{/([^/]+)$}, '/<b>\1</b>')
        %[<a class="btn btn-xs" href="subl://open?url=file://#{CGI::escape(file.to_s)}">#{name}</a>]
      end
    end.compact

    %[<div style="position: fixed; right: 6px; top: 5px; text-align: right; z-index: 100;">
      <button class="btn btn-xs" onclick="$('#lux-open-files').toggle();" style="padding:0 4px;">+</button>
      <div id="lux-open-files" style="display:none; background-color:#fff;">#{files.join('<br />')}</div>
    </div>]
  end
end

module Lux::View::DebugPlugin
  def render_part

    data = super

    if Lux.dev?
      files = [@template]
      files.unshift @caller_object.class.source_location if @caller_object
      data = Lux::View.wrap_with_debug_info files, data
    end

    data
  end
end

# add info to cell templates
module Lux::View::Cell::DebugPlugin
  def template name, &block
    data = super name, &block
    data = Lux::View.wrap_with_debug_info [self.class.source_location, @_template], data if Lux.dev?
    data
  end
end

if Lux.dev?
  Lux::View.prepend Lux::View::DebugPlugin
  Lux::View::Cell.prepend Lux::View::Cell::DebugPlugin
end
