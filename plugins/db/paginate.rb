class PaginatedArray < Array
  attr_reader :paginate_param, :paginate_page, :paginate_next

  def initialize(items, param:, page:, has_next:)
    super(items)
    @paginate_param = param
    @paginate_page  = page
    @paginate_next  = has_next
  end

  def paginate_first_ref
    first[:ref] rescue nil
  end

  def paginate_last_ref
    last[:ref] rescue nil
  end

  def paginate_opts
    { param: @paginate_param, page: @paginate_page, next: @paginate_next }
  end

  def paginate **args
    self
  end
end

def Paginate set, size: 20, param: :page, page: nil, count: nil, klass: nil
  page = Lux.current.params[param] if Lux.current.params[param].to_s =~ /\A\d+\z/
  page = page.to_i
  page = 1 if page < 1

  ret = set.offset((page-1) * size).limit(size+1).all

  has_next = ret.length == size + 1
  ret.pop if has_next

  if klass
    ret = ret.map { klass.new _1 }
  end

  PaginatedArray.new(ret, param: param, page: page, has_next: has_next)
end

module HtmlHelper
  extend self

  # paginate @list, first: 1
  def paginate list, in_opts = {}, &block
    in_opts[:first] ||= '&bull;'

    opts = if list.is_a?(Hash)
      list
    else
      return unless list.respond_to?(:paginate_next)

      {
        param:    list.paginate_param,
        page:     list.paginate_page,
        next:     list.paginate_next,
        last_ref:  list.paginate_last_ref,
        first_ref: list.paginate_first_ref
      }
    end

    if opts[:page].to_i < 2 && !opts[:next]
      # you can add block that will be rendered if no content is found
      return block && !list[0] ? yield : nil
    end

    ret = ['<div class="paginate"><div>']

    if opts[:page] > 1
      url = Url.current
      # opts[:page] == 1 ? url.delete(opts[:param]) : url.qs(opts[:param], '%s-d-%s' % [opts[:page]-1, opts[:first_ref]])
      opts[:page] == 1 ? url.delete(opts[:param]) : url.qs(opts[:param], opts[:page]-1)
      ret.push %[<a href="#{url.relative}" data-key="ArrowLeft">&larr;</a>]
    else
      ret.push %[<span>&larr;</span>]
    end

    ret.push %[<i>#{opts[:page] == 1 ? in_opts[:first] : opts[:page]}</i>]

    if opts[:next]
      url = Url.current
      url.qs(opts[:param], opts[:page]+1)
      ret.push %[<a href="#{url.relative}" data-key="ArrowRight">&rarr;</a>]
    else
      ret.push %[<span>&rarr;</span>]
    end

    ret.push '</div></div>'
    ret.join('')
  end
end

###

# Sequel::Model.db.extension :pagination

Sequel::Model.dataset_module do
  def page opts = {}
    Paginate self, **opts
  end
  alias :paginate :page
end
