# partialy extracted from
# https://github.com/rails/rails/blob/5-0-stable/activesupport/lib/active_support/core_ext/object/blank.rb

class Object
  def blank?
    !self
  end

  def empty?
    blank?
  end

  def present?
    !blank?
  end
end

class NilClass
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

    # test = !!(self =~ /^\s*$/)
    !(self =~ /[^\s]/)
  end
end

