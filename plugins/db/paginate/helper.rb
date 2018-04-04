module HtmlHelper

  def paginate list
    return unless list.respond_to?(:paginate_size)
    return nil if list.paginate_page == 1 && list.length < list.paginate_size

    ret = ['<div class="paginate"><div>']

    if list.paginate_page > 1
      url = Url.current
      list.paginate_page == 1 ? url.delete(list.paginate_param) : url.qs(list.paginate_param, list.paginate_page-1)
      ret.push %[<a href="#{url.relative}">&larr;</a>]
    else
      ret.push %[<span>&larr;</span>]
    end

    ret.push %[<i>#{list.paginate_page == 1 ? '&bull;' : list.paginate_page}</i>]

    if list.paginate_size == list.length
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

