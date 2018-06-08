class ViewCell
  @@cache = {}

  class << self
    # preche cell
    def init!
      @@cache.delete(self.to_s) if Lux.config(:compile_assets)

      return if @@cache[self.to_s]

      cache = @@cache[self.to_s] = {}

      inst_method = instance_methods(false).first
      data  = File.read(instance_method(inst_method).source_location[0].split(':').first).split('__END__', 2).last.to_s

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
      cells = Object.constants.map(&:to_s).select{ |it| it != 'ViewCell' && it.ends_with?('Cell') }.map(&:constantize) unless cells.first
      cells.inject('') { |t,w| t += w.css.to_s }
    end
  end

  ###

  define_method(:current) { Lux.current }
  define_method(:request) { Lux.current.request }
  define_method(:parent)  { @_parent }
  define_method(:render)  { render_template }

  def initialize parent
    @_parent = parent
    self.class.init!
  end

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

  # execute block only once per page
  def once
    Lux.current.once('cell-once-%s' % self.class) { yield }
  end
end
