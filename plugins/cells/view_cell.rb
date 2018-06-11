class ViewCell
  @@cache = {}

  class << self
    def base_folder
      Lux.root.join('app/cells/%s' % to_s.tableize.sub('_cells','')).to_s
    end

    # get cell css
    def css
      @@cache[self.to_s] ||= {}
      @@cache[self.to_s][:css] = nil  if Lux.config(:compile_assets)
      return if @@cache[self.to_s][:css]

      scss_file = '%s/cell.scss' % base_folder

      return unless File.exist?(scss_file)

      se = Sass::Engine.new(File.read(scss_file), :syntax => :scss)
      @@cache[self.to_s][:css] = se.render.gsub($/,'').gsub(/\s+/,' ').gsub(/([:;{}])\s+/,'\1')
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
  define_method(:params)  { Lux.current.params }
  define_method(:parent)  { @_parent }
  define_method(:render)  { render_template }

  def initialize parent
    @_parent = parent
  end

  def render
    render_template
  end

  def render_template name=:cell
    @@cache[self.class.to_s] ||= {}
    @@cache[self.class.to_s][:tpl] ||= {}

    @@cache[self.class.to_s][:tpl][name] ||= Proc.new do
      file = '%s/%s.haml' % [self.class.base_folder, name]
      data = File.read(file)
      Tilt[:haml].new { data }
    end.call

    @@cache[self.class.to_s][:tpl][name].render(self)
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

  def cell name
    w = ('%sCell' % name.to_s.classify).constantize
    w = w.new @_parent
    w
  end
end
