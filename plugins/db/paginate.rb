module HtmlHelper

  def paginate list
    return unless list.respond_to?(:paginate_next)
    return nil if list.paginate_page == 1 && !list.paginate_next

    ret = ['<div class="paginate"><div>']

    if list.paginate_page > 1
      url = Url.current
      list.paginate_page == 1 ? url.delete(list.paginate_param) : url.qs(list.paginate_param, list.paginate_page-1)
      ret.push %[<a href="#{url.relative}">&larr;</a>]
    else
      ret.push %[<span>&larr;</span>]
    end

    ret.push %[<i>#{list.paginate_page == 1 ? '&bull;' : list.paginate_page}</i>]

    if list.paginate_next
      url = Url.current
      url.qs(list.paginate_param, list.paginate_page+1)
      ret.push %[<a href="#{url.relative}">&rarr;</a>]
    else
      ret.push %[<span>&rarr;</span>]
    end

    ret.push '</div></div>'
    ret.join('')
  end

end

###

Sequel::Model.db.extension :pagination

Sequel::Model.dataset_module do
  def page size: 20, param: :page, page: nil, count: nil
    page = (page || Lux.current.request.params[param]).to_i
    page = 1 if page < 1

    # ret = paginate(page, size).all
    ret = offset((page-1) * size).limit(size+1).all

    has_next = ret.length == size + 1
    ret.pop if has_next

    ret.define_singleton_method(:paginate_param) do; param ;end
    ret.define_singleton_method(:paginate_page)  do; page; end
    ret.define_singleton_method(:paginate_next)  do; has_next; end

    ret
  end
end
