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
