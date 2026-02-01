# ovo sam ovako da mogu koristiti za sqlite i za pg
def Paginate set, size: 20, param: :page, page: nil, count: nil, klass: nil
  page = Lux.current.params[param] if Lux.current.params[param].respond_to?(:to_i)
  page = page.to_i
  page = 1 if page < 1

  # ret = paginate(page, size).all
  ret = set.offset((page-1) * size).limit(size+1).all

  has_next = ret.length == size + 1
  ret.pop if has_next

  if klass
    ret = ret.map { klass.new _1 }
  end

  ret.define_singleton_method(:paginate_param)    do; param ;end
  ret.define_singleton_method(:paginate_page)     do; page; end
  ret.define_singleton_method(:paginate_next)     do; has_next; end
  ret.define_singleton_method(:paginate_first_id) do; ret.first.id rescue nil; end
  ret.define_singleton_method(:paginate_last_id)  do; ret.last.id rescue nil; end
  ret.define_singleton_method(:paginate_opts)     do; ({ param: param, page: page, next: has_next }); end
  ret
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
        last_id:  list.paginate_last_id,
        first_id: list.paginate_first_id
      }
    end

    if opts[:page].to_i < 2 && !opts[:next]
      # you can add block that will be rendered if no content is found
      return block && !list[0] ? yield : nil
    end

    ret = ['<div class="paginate"><div>']

    if opts[:page] > 1
      url = Url.current
      # opts[:page] == 1 ? url.delete(opts[:param]) : url.qs(opts[:param], '%s-d-%s' % [opts[:page]-1, opts[:first_id]])
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
