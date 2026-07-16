class HtmlTable
  def initialize scope, opts={}
    @sort_param    = 't-sort'
    @scope         = scope
    @opts          = opts
    @cols          = []
    @searches      = []
    @default_order = nil
    @scope_filter  = nil
  end

  def before scope
    scope
  end

  # t.col :is_active, as: :boolean
  def col *args, &block
    if args.first.is_a?(Hash)
      opts = args.first
    else
      opts = (args[1] || {}).dup
      opts[:field] = args[0] if args[0].is_a?(Symbol)
    end

    opts[:block] = block if block

    @cols.push opts
  end

  # tb.render
  def render
    params = Lux.current.request.params

    if sort = params[@sort_param]
      direction, field = sort.split('-', 2)
    else
      direction, field = initial_sort
    end

    if direction && field && @scope.respond_to?(:order)
      @scope = @scope.xwhere("#{field.db_safe} is not null")
      @scope = @scope.order(direction == 'a' ? Sequel.asc(field.to_sym) : Sequel.desc(field.to_sym))
    elsif !sort
      @scope = @default_order.call(@scope) if @default_order
    end

    @scope = @scope_filter.call(@scope) if @scope_filter

    apply_searches params

    @scope = before @scope

    return unless @scope.first

    prepare_as_blocks

    # data-cols fingerprint: forces a new <table> node when column set/widths
    # change across pjax morphs (avoids Firefox fixed-layout width cache).
    table_key = @cols.map { |c| [c[:field], c[:title], c[:width], c[:min_width]].join(':') }.join('|')

    HtmlTag.div(class: 'app-table') do |n|
      n.table(class: @opts[:class], 'data-cols': table_key) do |n|
        n.colgroup do |n|
          for opts in @cols
            render_col n, opts
          end
        end

        n.thead do |n|
          n.tr do |n|
            for opts in @cols
              render_th n, opts
            end
          end
        end

        n.tbody do |n|
          for object in @scope.all
            render_tr n, object
          end
        end
      end
    end
  end

  private

  def col_style opts
    style = []
    style.push 'width: %dpx' % opts[:width] if opts[:width]
    style.push 'min-width: %dpx' % opts[:min_width] if opts[:min_width]
    style
  end

  def render_col n, opts
    style = col_style(opts)
    if style.first
      n.col style: style.join('; ')
    else
      n.col
    end
  end

  def render_th n, opts
    th_opts = {}

    style = col_style(opts)

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

    title = opts[:title]
    title = opts[:field].to_s.humanize if title.nil? && opts[:field]

    if opts[:sort]
      sort = opts[:sort]
      field = sort.is_a?(Symbol) && sort != :a && sort != :d ? sort : opts[:field]
      direction = Lux.current.request.params[@sort_param].to_s[0, 2] == 'a-' ? 'd-' : 'a-'

      title = HtmlTag.span(class: 'table-sort table-sort-%ssort' % direction) do |n|
        n.a(href: build_qs(@sort_param, direction + field.to_s)) { title }
      end
    end

    n.th title, **th_opts
  end

  def render_tr n, object
    tr_opts = {}

    if @onclick
      tr_opts[:onclick] = @onclick.call object
    end

    # Do not put HTML width= on <td> — Firefox table-layout:fixed treats it
    # inconsistently after morph. Column widths live on <col>/<th> only.
    allowed = [:id, :class, :href, :style, :align, :onclick]

    n.tr(**tr_opts.slice(*allowed)) do |n|
      for opts in @cols
        content = render_cell object, opts
        n.td content, **opts.slice(*allowed)
      end
    end
  end

  def render_cell object, opts
    if opts[:as]
      opts[:as].call object
    elsif opts[:block]
      opts[:block].call object
    elsif opts[:field]
      object.send(opts[:field])
    else
      raise ArgumentError, 'HtmlTable column requires :field, :as, or a block'
    end
  end

  def apply_searches params
    @searches.each do |qs, _type, _opts, block|
      value = params[qs.to_s]
      @scope = block.call(@scope, value) if value.to_s != ''
    end
  end

  def initial_sort
    col = @cols.find { |c| c[:sort] == :a || c[:sort] == :d }
    return [nil, nil] unless col
    [col[:sort].to_s, col[:field].to_s]
  end

  def build_qs key, value
    req = Lux.current.request
    params = req.params.merge(key => value)
    qs = params.map { |k, v| "#{k}=#{v}" }.join('&')
    "#{req.path}?#{qs}"
  end

  def prepare_as_blocks
    for col in @cols
      if col[:as]
        m = 'as_%s' % col[:as]
        raise ArgumentError.new('Table as block "%s" not defined' % col[:as]) unless respond_to?(m, true)
        col[:as] = send m, col
      end
    end
  end
end
