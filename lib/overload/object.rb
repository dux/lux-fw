class Object

  def or _or
    self.blank? || self == 0 ? _or : self
  end

  def try *args
    return nil if self.class == NilClass
    self.send(*args)
  end

  def die desc=nil, exp_object=nil
    desc ||= 'died without desc'
    desc = '%s: %s' % [exp_object.class, desc] if exp_object
    puts desc.red
    raise desc
  end

  # this will capture plain Hash and HashWithIndifferentAccess
  def is_hash?
    self.class.to_s.index('Hash') ? true : false
  end

  def is_array?
    self.class.to_s.index('Array') ? true : false
  end

  def is_string?
    self.class.to_s == 'String' ? true : false
  end

  def is_false?
    self.class.name == 'FalseClass' ? true : false
  end

  def is_true?
    self ? true :false
  end

  def is_numeric?
    Float(self) != nil rescue false
  end

  def is_symbol?
    self.class.to_s == 'Symbol' ? true : false
  end

  def is_boolean?
    self.class == TrueClass || self.class == FalseClass
  end

end

# if we dont have awesome print in prodction, define mock
method(:ap) rescue Proc.new do
  class Object
    def ap(*args)
      puts args
    end
  end
end.call

