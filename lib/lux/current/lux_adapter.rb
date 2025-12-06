module Lux
  def current
    Thread.current[:lux] ||= Lux::Current.new('/mock')
  end
end

# exposes lux shortcut anywhere
class Object
  def lux
    Lux.current
  end
end
