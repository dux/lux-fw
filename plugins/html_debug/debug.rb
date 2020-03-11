class Lux::Template
  def self.wrap_with_debug_info files, data
    return data unless Lux.current.request.params[:debug] == 'render'

    files = [files] unless files.is_a?(Array)
    files = files.compact.map do |file|
      file, prefix = file.sub(/'$/, '').sub(Lux.root.to_s, '.').split(':in `')
      prefix = ' # %s' % prefix if prefix

      %[<a href="subl://open?url=file:/%s" style="color: #fff;" onmousedown="setTimeout(function() { $('#debug-toggle').click() }, 300)">%s%s</a>] % [Url.escape(Lux.root.join(file).to_s), file.split(':').first, prefix]
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
    return if Lux.env.production?

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

module Lux::Template::DebugPlugin
  def render *args, &block
    Lux::Template.wrap_with_debug_info @template, super
  end
end

# add info to cell templates
module Lux::ViewCell::DebugPlugin
  def template *args
    Lux::Template.wrap_with_debug_info caller.first, super
  end
end

if Lux.env.dev?
  Lux::Template.prepend Lux::Template::DebugPlugin
  Lux::ViewCell.prepend Lux::ViewCell::DebugPlugin
end
