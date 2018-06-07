class HtmlCell
  @@cache = {}

  class << self
    # create and render cell
    def render context, *args

      # init template and css
      init!

      cell = new *args
      cell.parent = context
      data = ''

      Lux.current.once('cell-once-%s' % self) do
        src = instance_method(:initialize).source_location[0].split(':').first
        Lux.current.files_in_use.push src.sub(Lux.root.to_s+'/', '')

        if cell.respond_to?(:once)
          data = cell.once
        end
      end

      data + cell.render
    rescue
      Lux::Error.inline "%s render error" % self
    end

    def init!
      @@cache.delete(self.to_s) if Lux.config(:compile_assets)

      return if @@cache[self.to_s]

      cache = @@cache[self.to_s] = {}

      data  = File.read(instance_method(:initialize).source_location[0].split(':').first).split('__END__', 2).last.to_s

      for part in  data.split("\n@@ ")
        key, value = part.split("\n", 2).map(&:chomp)

        next unless key.present?

        key = key.downcase
        key = 'css' if key == 'scss'

        if key == 'css'
          begin
            se = Sass::Engine.new(value, :syntax => :scss)
            cache[:css] = se.render.gsub($/,'').gsub(/\s+/,' ').gsub(/([:;{}])\s+/,'\1')
          rescue
            puts 'Error: %s SASS compile error'.red % self
            puts $!.message
            exit
          end
        elsif ['haml', 'erb'].include?(key)
          cache[:template] = Tilt[key.to_sym].new { value }
        end
      end
    end

    # get cell css
    def css
      init!
      @@cache[self.to_s][:css]
    end

    # get css for all cells
    def all_css *cells
      cells = Object.constants.map(&:to_s).select{ |it| it != 'HtmlCell' && it.ends_with?('Cell') }.map(&:constantize) unless cells.first
      cells.inject('') { |t,w| t += w.css.to_s }
    end
  end

  ###

  define_method(:current) { Lux.current }
  define_method(:request) { Lux.current.request }
  define_method(:parent)  { @_parent }
  define_method(:parent=) { |it| @_parent = it }
  define_method(:render)  { render_template }

  def render
    render_template
  end

  def render_template
    @@cache[self.class.to_s][:template].render(self)
  end

  # tag :div, { 'class'=>'iform' } do
  def tag name=nil, opts={}, data=nil
    return HtmlTagBuilder unless name

    data = yield(opts) if block_given?
    HtmlTagBuilder.tag name, opts, data
  end
end
