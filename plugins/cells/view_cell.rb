class ViewCell
  class Loader
    def initialize parent
      @parent = parent
    end

    def method_missing m, vars={}
      ViewCell.get(m, @parent, vars)
    end
  end

  class_callbacks :before

  @@cache = {}

  class << self
    def get name, parent, vars={}
      w = ('%sCell' % name.to_s.classify).constantize
      w = w.new parent, vars
      w
    end

    def base_folder
      Lux.root.join('app/cells/%s' % to_s.tableize.sub('_cells','')).to_s
    end

    def get_all_cell_classes
      # all base cells have to inherit from ViewCell base class
      ObjectSpace
        .each_object(Class)
        .select{ |it| ViewCell === it.ancestors[1] }
        .to_a
    end

    # get cell css
    def css
      require 'sassc'

      scss_files = Dir["#{base_folder}/**/*.scss"] + Dir["#{base_folder}/**/*.css"]
      data       = scss_files.sort.map { |file| File.read(file) }.join("\n\n")

      se = SassC::Engine.new(data, :syntax => :scss)
      se.render.gsub($/,'').gsub(/\s+/,' ').gsub(/([:;{}])\s+/,'\1')
    end

    # get cell js
    def js
      Dir["#{base_folder}/**/*"]
        .select { |it| ['js', 'coffee'].include?(it.split('.').last) }
    end

    # get css for all cells
    def all_css
      cells = Object.constants.map(&:to_s).select{ |it| it != 'ViewCell' && it.ends_with?('Cell') }.map(&:constantize)
      cells.inject('') { |t,w| t += w.css.to_s }
    end

    # get css for all cells
    def all_js
      cells = Object.constants.map(&:to_s).select{ |it| it != 'ViewCell' && it.ends_with?('Cell') }.map(&:constantize)
      total = cells.inject([]) { |t,w| t += w.js }

      total.map do |file|
        asset = SimpleAssets::Asset.new file
        asset.compile.split("\n//#").first
      end.join("\n\n")
    end
  end

  ###

  define_method(:current) { Lux.current }
  define_method(:request) { Lux.current.request }
  define_method(:params)  { Lux.current.request.params }

  def initialize parent, vars={}
    @_parent = parent

    class_callback :before

    vars.each { |k,v| instance_variable_set "@#{k}", v}

    # add runtime file reference
    if m = self.class.instance_methods(false).first
      src = method(m).source_location[0].split(':').first
      src = src.sub(Lux.root.to_s+'/', '')
      Lux.log " #{src}" unless Lux.current.files_in_use.include?(src)
      Lux.current.files_in_use src
    end
  end

  def parent &block
    if block_given?
      @_parent.instance_exec &block
    else
      @_parent
    end
  end

  # if block is passed, template render will be passed as an argument
  def template name=:cellm, &block
    tpl = 'cell-tpl-%s-%s' % [self.class, name]

    tpl = Lux.ram_cache(tpl) do
      file = '%s/%s.haml' % [self.class.base_folder, name]
      file = file.sub(Lux.root.to_s+'/', '')

      Lux.log ' ' + file unless Lux.current.files_in_use(file)

      Tilt[:haml].new { File.read(file) }
    end

    data = tpl.render(self)
    data = block.call(data) if block
    data
  end

  # tag :div, { 'class'=>'iform' } do
  def tag name=nil, opts={}, data=nil
    return HtmlTagBuilder unless name

    data = yield(opts) if block_given?
    HtmlTagBuilder.tag name, opts, data
  end

  # execute block only once per page
  def once id=nil
    id ||= self.class
    Lux.current.once('cell-once-%s' % id) { yield }
  end

  def cell name=nil
    return parent.cell unless name

    w = ('%sCell' % name.to_s.classify).constantize
    w = w.new @_parent
    w
  end
end
