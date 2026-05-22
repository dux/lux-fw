require_relative '../lux/utils/boolean'

class TrueClass
  include Lux::Utils::Boolean

  def to_i
    1
  end
end

class FalseClass
  include Lux::Utils::Boolean

  def to_i
    0
  end
end

class Numeric
  def to_b
    self > 0
  end
end

class Object
  def to_b
    !!Lux::Utils::Boolean.parse(self)
  end
end
