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
end