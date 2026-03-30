module Lux
  def current
    Thread.current[:lux] ||= Lux::Current.new('/mock')
  end
end

# exposes lux shortcut anywhere
class Object
  def lux
    Thread.current[:lux]
  end
end
