module Lux
  def error data=nil
    if data
      raise Lux::Error.new(500, data)
    else
      Lux::Error
    end
  end
end