# class TableBuilder
#   def callback *fields
#     onclick { |o| 'Dialog.callback(%s)' % o.slice(*fields).to_json }
#   end

#   def search_on *fields
#     # find all text fields in a object and search on all of them
#     filter(:q, :text) do |scope, value, qs|
#       info 'Searched on: %s' % fields.map{ |el| el.to_s.wrap(:b) }.to_sentence
#       scope.xlike(value, *fields) if value
#       s_widget :search, name: qs
#     end
#   end
# end

# = table City.order(:name).xlike(params[:q], :name, :code) do |t|
#   - t.col :image, as: :image
#   - t.col :is_active, as: :boolean
#   - t.col :name
#   - t.col :country, as: :admin_link
#
# tb = TableBuilder.new class: 'table hover'
# tb.as(:boolean) do |opts|
#   opts[:width] ||= 100
#   opts[:align] ||= :center
#   proc { |o| o.send(opts[:field]) ? 'Yes'.wrap(:span, style:'color:#080') : '-' }
# end
# tb.filter :q, :text

class TableBuilder
  FilterOpts ||= Class.new Struct.new(:qs, :type, :opts, :value, :render)

  attr_accessor :scope
  attr_reader   :filters

  def initialize scope, opts={}
    @scope    = scope
    @opts     = opts
    @cols     = []
    @info     = []
    @as       = {}
    @searches = []
    @filter   = {}
    @filters  = []
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
  #   src = o.send(opts[:field])
  #   src.present? ? %[<img src="#{src}" style="width:100%; margin: -5px 0;" />] : ''
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

  ###

  # block adds paging to scope at the end functions as a last filter to scope
  # tb.render { |scope| scope.page }
  def render &block
    body   = []
    header = []

    render_prepare_as
    render_apply_filters

    @scope = block.call(@scope) if block

    HtmlTagBuilder.table(class: @opts[:class], 'data-fields': @cols.map{ |o| }) do |n|
      n.thead do |n|
        n.tr do |n|
          for opts in @cols
            th_opts = {}

            style = []
            style.push 'width: %dpx' % opts[:width] if opts[:width]
            style.push 'text-align: %s' % opts[:align] if opts[:align]
            th_opts[:style] = style.join('; ') if style.first

            title   = opts[:title]
            title ||= opts[:field].to_s.humanize if opts[:field]

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
          end

          n.tr(tr_opts) do |n|
            for opts in @cols
              content = render_row object, opts
              n.td(opts) { content }
            end
          end
        end
      end
    end
  end

  private

  def render_prepare_as
    for opts in @cols
      if as = opts[:as]
        raise ArgumentError.new('Table as block "%s" not defined' % as) unless @as[as]
        opts[:block] = @as[as].call(opts)
      end
    end
  end

  def render_apply_filters
    for qs, type, opts, block in @searches
      opts = FilterOpts.new(qs, type, opts)

      opts.value = Lux.current.request.params[qs]

      if opts.value.present?
        @scope = block.call(scope, opts.value)
        #  @scope = data[2].call @scope, value
      end

      opts.render = @filter[type].call(opts)
      @filters.push opts
    end

    #  @scope =  @scope.page size: @opts[:size] || 30
  end

  def render_row object, opts
    content =
    if as = opts[:as]
      raise ArgumentError.new('Table as block "%s" not defined' % as) unless opts[:block]
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