module Lux
  def current
    Thread.current[:lux] ||= Lux::Current.new('/mock')
  end
end