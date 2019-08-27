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
  attr_accessor :scope
  attr_reader   :filters

  def initialize opts={}
    @opts    = opts
    @cols    = []
    @info    = []
    @as      = {}
    @filters = {}
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

  def info text=nil
    @info.push text if text
    @info
  end

  # t.href { |object| object.path }
  def href &block
    @href = block
  end

  # t.onclick { |object| "window.open('%s')" % object.dashboard_path }
  def onclick &block
    @onclick = block
  end

  # t.as(:image) do |opts|
  #   opts[:width] ||= 120
  #   proc do |o|
  #     src = o.send(opts[:field])
  #     src.present? ? %[<img src="#{src}" style="width:100%; margin: -5px 0;" />] : ''
  #   end
  # end
  def as name, &block
    @as[name] = block
  end

  def filter querystring, type=:text, opts={}, &block
    if type
      @filters[querystring] = [type, opts, block]
    else
      # set type to nil to delete it
      # useful to set common query as a default and be able to remove it unless you need it
      @filters.delete querystring
    end
  end

  ###

  def render scope=nil
    @scope = scope if scope
    body   = []
    header = []

    render_prepare_as
    render_apply_filters

    HtmlTagBuilder.table(class: @opts[:class], 'data-fields': @cols.map{ |o| }) do |n|
      n.thead do |n|
        n.tr do |n|
          for opts in @cols
            th_opts = {}
            th_opts[:style] = 'width: %dpx;' % opts[:width] if opts[:width]
            title   = opts[:title]
            title ||= opts[:field].to_s.humanize if opts[:field]

            n.th(th_opts) { title }
          end
        end
      end

      n.tbody do |n|
        for object in @scope
          tr_opts = {}

          if @onclick
            tr_opts[:onclick] = @onclick.call object
          elsif @href
            tr_opts[:href] = @href.call object
          end

          n.tr(tr_opts) do |n|
            for opts in @cols
              content, opts = render_row object, opts
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
    for name, data in @filters
      value = Lux.current.request.params[name]
      if value.present?
        @scope = data[2].call @scope, value
      end
    end

     @scope =  @scope.page size: @opts[:size] || 30
  end

  def render_row object, opts
    row_opts = {}

    content =
    if opts[:block]
      opts[:block].call object
    elsif opts[:field]
      object.send(opts[:field])
    else
      'no block or field'
    end

    [content, row_opts]
  end
end