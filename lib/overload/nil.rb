class NilClass
  # NilClass#dup is built-in since Ruby 2.4 - removed custom implementation.

  def is? klass
    false
  end
end