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
