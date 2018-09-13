module Sequel::Plugins::LuxSimplePaginate
  module DatasetMethods
    def page size: 20, param: :page, page: nil, count: nil
      page = (page || Lux.current.request.params[param]).to_i
      page = 1 if page < 1

      ret = paginate(page, size).all
      ret.define_singleton_method(:paginate_param) do; param ;end
      ret.define_singleton_method(:paginate_page)  do; page ;end
      ret.define_singleton_method(:paginate_size)  do; size ;end

      ret
    end
  end
end

Sequel::Model.db.extension :pagination
Sequel::Model.plugin :lux_simple_paginate
