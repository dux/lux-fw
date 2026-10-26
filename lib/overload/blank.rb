class Object
  # ActiveSupport semantics: anything that answers empty? is blank when empty
  def blank?
    respond_to?(:empty?) ? !!empty? : !self
  end

  def present?
    !blank?
  end
end

class NilClass
  def present?
    false
  end

  def blank?
    true
  end
end

class FalseClass
  def blank?
    true
  end
end

class TrueClass
  def blank?
    false
  end
end

class Array
  def blank? = empty?
end

class Hash
  def blank? = empty?
end

class Numeric
  def blank?
    false
  end
end

class Time
  def blank?
    false
  end
end

class String
  def blank?
    empty? || !match?(/[^[:space:]]/)
  rescue ArgumentError, Encoding::CompatibilityError
    false # undecodable bytes are content, not blank
  end
end

