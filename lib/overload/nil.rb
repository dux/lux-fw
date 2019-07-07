class NilClass
  def empty?
    true
  end

  def present?
    false
  end

  def dup
    nil
  end

  def is? value
    true
  end
end