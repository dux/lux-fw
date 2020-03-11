class TableBuilder
  DEFINES    ||= {}
  FilterOpts ||= Class.new Struct.new(:qs, :type, :opts, :value, :render)

  attr_reader :filters, :scope, :opts

  class << self
    # TableBuilder.define(:admin, ApplicationHelper) do ...
    def define name, helper_klass=nil, &block
      # just store the func
      DEFINES[name] = block

      if helper_klass
        # if giver helper class, inject helper method to view
        helper_klass.define_method(name) do |sql_scope, opts={}, &block|
          TableBuilder.call(name, self, sql_scope, opts, &block)
        end
      end
    end

    # call and render table
    def call name, helper_scope, sql_scope, opts={}, &block
      raise ArgumentError.new('Table named "%s" not defined' % name) unless DEFINES[name]

      tb = new sql_scope, opts         # create instance
      tb.instance_exec &DEFINES[name]  # init
      block.call tb                    # fill
      tb.render_prepare_as
      tb.render_apply_filters helper_scope
      tb.draw_exec                     # draw table
    end
  end

  ###

  def initialize scope, opts
    opts[:id] ||= Crypt.sha1(caller.to_s)[0, 4]

    @sort_param   = '%s-sort' % opts[:id]
    @scope        = scope
    @opts         = opts
    @cols         = []
    @info         = []
    @as           = {}
    @searches     = []
    @filter       = {}
    @filters      = []
  end

  def tag
    HtmlTagBuilder
  end

  # t.col :is_active, as: :boolean
  def col *args, &block
    if args.first.is_a?(Hash)
      opts = args.first
    else
      opts = args[1] ||= {}
      opts.merge!(field: args[0]) if args[0].class == Symbol
    end

    opts[:block] = block if block

    @cols.push opts
  end

  # push info text on stack, manual render
  def info text=nil
    @info.push text if text
    @info
  end

  # define row level href path
  # t.href { |object| object.path }
  def href &block
    @href = block
  end

  # define row level onclick event
  # t.onclick { |object| "window.open('%s')" % object.dashboard_path }
  def onclick &block
    @onclick = block
  end

  # t.as(:image) do |o, opts|
  #   opts[:width] ||= 120
  #   proc do |o|
  #     src = o.send(opts[:field])
  #     src.present? ? %[<img src="#{src}" style="width:100%; margin-top: -3px; vertical-align: middle;" />] : ''
  #   end
  # end
  def as name, &block
    @as[name] = block
  end

  # how  will the filter be rendred
  # tb.filter :text do |qs, value|
  #   s _widget :search, name: qs
  # end
  def filter type, &block
    @filter[type] = block
  end

  # how will the filter be searched, usually overriten
  # def filter type, &block
  #   @searches[type] = block
  # end

  # on page defiend search
  # - t.search :q do |scope, value|
  #   scope.xlike(value, :name)
  def search qs, type=nil, opts={}, &block
    @searches.push [qs, type || :text, opts, block]
  end

  # define a scope as a param to add post query filters and pagination
  def before &block
    @scope_filter = block
  end

  # just store the block, used in define
  def draw &block
    @draw = block
  end

  # set default order
  def default_order &block
    @default_order = block
  end

  # draws table in helper scope
  def draw_exec
    @helper_scope.instance_exec(self, &@draw)
  end

  ###

  # block adds paging to scope at the end functions as a last filter to scope
  # tb.render
  def render render_opts={}
    body   = []
    header = []

    if sort = Lux.current.request.params[@sort_param]
      direction, field = sort.split('-', 2)
      @scope = @scope.order(direction == 'a' ? Sequel.asc(field.to_sym) : Sequel.desc(field.to_sym))
    else
      @scope = @default_order.call(@scope) if @default_order
    end

    @scope = @scope_filter.call(@scope) if @scope_filter

    render_opts[:class] = 'table-builder %s' % render_opts[:class]

    HtmlTagBuilder.table(class: render_opts[:class], 'data-fields': @cols.map{ |o| }) do |n|
      n.thead do |n|
        n.tr do |n|
          for opts in @cols
            th_opts = {}

            style = []
            style.push 'width: %dpx' % opts[:width] if opts[:width]

            if align = opts[:align]
              case align
              when :r
                align = :right
              when :c
                align = :center
              when :l
                align = :left
              end

              style.push 'text-align: %s' % align
            end

            th_opts[:style] = style.join('; ') if style.first

            title  = opts[:title]
            title = opts[:field].to_s.humanize if title.nil? && opts[:field]

            if sort = opts[:sort]
              field     = sort.is_a?(Symbol) ? sort : opts[:field]
              direction = Lux.current.request.params[@sort_param].to_s[0, 2] == 'a-' ? 'd-' : 'a-'

              title = tag.span(class: 'table-sort table-sort-%ssort' % direction) do |n|
                n.a(href: Url.qs(@sort_param, direction + field.to_s) ) { title }
              end
            end

            n.th(th_opts) { title }
          end
        end
      end

      n.tbody do |n|
        for object in @scope.all
          tr_opts = {}

          if @onclick
            tr_opts[:onclick] = @onclick.call object
          elsif @href
            tr_opts[:href] = @href.call object
            tr_opts.delete :href unless tr_opts[:href]
          end

          allowed = [:id, :class, :href, :style, :width, :align, :onclick]

          n.tr(tr_opts.slice(*allowed)) do |n|
            for opts in @cols
              content = render_row object, opts
              n.td(opts.slice(*allowed)) { content }
            end
          end
        end
      end
    end
  end

  def render_prepare_as
    for opts in @cols
      if as = opts[:as]
        raise ArgumentError.new('Table as block "%s" not defined' % as) unless @as[as]
        opts[:block] = @as[as].call(opts)
      end
    end
  end

  def render_apply_filters helper_scope
    @helper_scope = helper_scope

    for qs, type, opts, block in @searches
      opts = FilterOpts.new(qs, type, opts)

      opts.value = Lux.current.request.params[qs]

      if opts.value.present?
        @scope = block.call(scope, opts.value)
      end

      raise 'Table fitler type "%s" not defined' % type unless @filter[type]

      opts.render = @helper_scope.instance_exec opts, &@filter[type]

      @filters.push opts
    end
  end

  private

  def render_row object, opts
    content =
    if opts[:as]
      raise ArgumentError.new('Table as block "%s" not defined' % opts[:as]) unless opts[:block]
      opts[:block].call(object)
    elsif opts[:block]
      opts[:block].call object
    elsif opts[:field]
      object.send(opts[:field])
    else
      'no block or field'
    end

    content
  end
end
