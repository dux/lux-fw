class Object
  def blank?
    !self
  end

  def present?
    !blank?
  end
end

class NilClass
  def empty?
    true
  end

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
  def blank?
    self.length == 0
  end
end

class Hash
  def blank?
    self.keys.length == 0
  end
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
    return true if self.length == 0

    !(self =~ /[^\s]/)
  end
end

