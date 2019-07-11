require_relative 'view'

class Lux::View::Cell
  class Loader
    def initialize parent
      @parent = parent
    end

    def method_missing m, vars={}
      ViewCell.get(m, @parent, vars)
    end
  end

  ###

  class_callback :before

  @@cache = {}

  class << self
    def get name, parent, vars={}
      w = ('%sCell' % name.to_s.classify).constantize
      w = w.new parent, vars
      w
    end

    # delegate current scope methods to parent binding
    def delegate *list
      list.each do |el|
        define_method(el) { |*args, &block| parent.send(el, *args, &block) }
      end
    end
  end

  ###

  define_method(:current) { Lux.current }
  define_method(:request) { Lux.current.request }
  define_method(:params)  { Lux.current.request.params }

  def initialize parent, vars={}
    @_parent = parent

    Object.class_callback :before, self

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
      file = '%s/%s.haml' % [self.class.source_location(true), name]
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

  def cache *args
    Lux.cache.fetch(*args) { yield }
  end
end
