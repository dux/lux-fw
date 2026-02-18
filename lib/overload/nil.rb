class NilClass
  def dup
    nil
  end

  def is? klass
    false
  end
end