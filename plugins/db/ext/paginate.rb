module Lux
module Utils
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

  Lux::Utils::PaginatedArray.new(ret, param: param, page: page, has_next: has_next)
end

###

Sequel::Model.dataset_module do
  def page opts = {}
    Paginate self, **opts
  end
  alias :paginate :page
end
