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

# Top-level alias so apps can write `value.is_a?(Boolean)` instead of the
# longer `Lux::Utils::Boolean`. Works because both TrueClass and FalseClass
# `include Lux::Utils::Boolean` above.
Boolean = Lux::Utils::Boolean unless defined?(Boolean)
