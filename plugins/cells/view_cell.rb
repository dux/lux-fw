class ViewCell
  @@cache = {}

  class << self
    def get name, parent
      w = ('%sCell' % name.to_s.classify).constantize
      w = w.new parent
      w
    end

    def base_folder
      Lux.root.join('app/cells/%s' % to_s.tableize.sub('_cells','')).to_s
    end

    # get cell css
    def css
      scss_files = Dir["#{base_folder}/*.scss"] + Dir["#{base_folder}/*.css"]
      data       = scss_files.sort.map { |file| File.read(file) }.join("\n\n")

      se = Sass::Engine.new(data, :syntax => :scss)
      se.render.gsub($/,'').gsub(/\s+/,' ').gsub(/([:;{}])\s+/,'\1')
    end

    # get css for all cells
    def all_css
      cells = Object.constants.map(&:to_s).select{ |it| it != 'ViewCell' && it.ends_with?('Cell') }.map(&:constantize)
      cells.inject('') { |t,w| t += w.css.to_s }
    end
  end

  ###

  define_method(:current) { Lux.current }
  define_method(:request) { Lux.current.request }
  define_method(:params)  { Lux.current.request.params }
  define_method(:parent)  { @_parent }
  define_method(:render)  { render_template }

  def initialize parent
    @_parent = parent
  end

  def render
    render_template
  end

  def render_template name=:cell
    # template = 'app/cells/%s/%s' % [klass, name]
    template = 'cell-template-%s-%s' % [self.class, name]

    template = Lux.ram_cache(template) do
      file = '%s/%s.haml' % [self.class.base_folder, name]
      Lux.current.files_in_use.push file

      data = File.read(file)
      Tilt[:haml].new { data }
    end

    template.render(self)
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
