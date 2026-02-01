class HtmlTable
  def initialize scope, opts={}
    # tpl = caller[0,10].select{ _1.include?('.haml') }.first || 'n/a'
    # opts[:id] ||= Crypt.sha1(tpl)[0, 4]
    @sort_param   = 't-sort'
    @scope        = scope
    @opts         = opts
    @cols         = []
    @searches     = []
  end

  def before scope
    scope
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

  # define row level onclick event
  # t.onclick { |object| "window.open('%s')" % object.dboard_path }
  def onclick &block
    @onclick = block
  end

  # on page defiend search
  # - t.search :q do |scope, value|
  #   scope.xlike(value, :name)
  def search qs, type=nil, opts={}, &block
    @searches.push [qs, type || :text, opts, block]
  end

  ###

  # block adds paging to scope at the end functions as a last filter to scope
  # tb.render
  def render
    body   = []
    header = []

    if sort = Lux.current.request.params[@sort_param]
      direction, field = sort.split('-', 2)
      if @scope.respond_to?(:order)
        @scope = @scope.xwhere("#{field.db_safe} is not null")
        @scope = @scope.order(direction == 'a' ? Sequel.asc(field.to_sym) : Sequel.desc(field.to_sym))
      end
    else
      @scope = @default_order.call(@scope) if @default_order
    end

    @scope = @scope_filter.call(@scope) if @scope_filter

    @scope = before @scope

    return unless @scope.first

    prepare_as_blocks

    HtmlTag.div(class: 'app-table') do |n|
      n.table(class: @opts[:class], 'data-fields': @cols.map{ |o| }) do |n|
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

              title = opts[:title]
              title = opts[:field].to_s.humanize if title.nil? && opts[:field]

              if sort = opts[:sort]
                field     = sort.is_a?(Symbol) ? sort : opts[:field]
                direction = Lux.current.request.params[@sort_param].to_s[0, 2] == 'a-' ? 'd-' : 'a-'

                title = HtmlTag.span(class: 'table-sort table-sort-%ssort' % direction) do |n|
                  n.a(href: Url.qs(@sort_param, direction + field.to_s) ) { title }
                end
              end

              n.th title, th_opts
            end
          end
        end

        n.tbody do |n|
          for object in @scope.all
            tr_opts = {}

            if @onclick
              tr_opts[:onclick] = @onclick.call object
            end

            allowed = [:id, :class, :href, :style, :width, :align, :onclick]

            n.tr(tr_opts.slice(*allowed)) do |n|
              for opts in @cols
                content = render_row object, opts
                n.td content, opts.slice(*allowed)
              end
            end
          end
        end
      end
    end
  end

  private

  def render_row object, opts
    content =
    if opts[:as]
      opts[:as].call object
    elsif opts[:block]
      opts[:block].call object
    elsif opts[:field]
      object.send(opts[:field])
    else
      'no block or field'
    end

    content
  end

  def prepare_as_blocks
    for col in @cols
      if col[:as]
        m = 'as_%s' % col[:as]
        raise ArgumentError.new('Table as block "%s" not defined' % col[:as]) unless respond_to?(m)
        col[:as] = send m, col
      end
    end
  end
end
