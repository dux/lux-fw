module Enumerable
  def index_by
    each_with_object({}) { |el, h| h[yield(el)] = el }
  end

  def index_with
    each_with_object({}) { |el, h| h[el] = yield(el) }
  end

  def many?
    count > 1
  end
end
