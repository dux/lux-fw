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

  def is? klass
    true
  end
end