module Enumerable
  def index_by
    each_with_object({}) { |el, h| h[yield(el)] = el }
  end

  def many?
    count > 1
  end
end
