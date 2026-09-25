ApplicationHelper.class_eval do

  def request
    Lux.current.request
  end

  def response
    Lux.current.response
  end

end
