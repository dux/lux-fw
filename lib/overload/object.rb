class Object
  LUX_AUTO_LOAD ||= {}

  def self.const_missing klass, path=nil
    unless LUX_AUTO_LOAD.keys.first
      for file in `find ./app -type f -name '*.rb'`.split($/)
        klass_file = file.split('/').last.sub('.rb', '').classify
        LUX_AUTO_LOAD[klass_file] ||= [false, file]
      end
    end

    klass = klass.to_s if klass.class == Symbol
    path  = LUX_AUTO_LOAD[klass]
    error = %{Can't find and autoload module/class "%s"} % klass

    if path
      if path[0]
        raise NameError.new('%s, found file "%s" is not defineing it.' % [error, path[1]])
      else
        path[0] = true
        require path[1].sub('.rb', '')
        Object.const_get(klass)
      end
    else
      raise NameError.new('%s. Scanned all files in ./app folder' % error)
    end
  end

  ###

  # @foo.or(2)
  def or _or=nil, &block
    self.blank? || self == 0 ? (block ? block.call : _or) : self
  end

  def and &block
    block.call(self) if self.present?
  end

  def try *args, &block
    return nil if self.class == NilClass
    data = self.send(*args) || return
    block_given? ? block.call(data) : data
  end

  def die desc=nil, exp_object=nil
    desc ||= 'died without desc'
    desc = '%s: %s' % [exp_object.class, desc] if exp_object
    puts desc.red
    puts caller.slice(0, 10)
    raise desc
  end

  # this will capture plain Hash and Hash With Indifferent Access
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
    ['true', 'on', '1'].include?(to_s)
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

  def is_a! klass, error = nil
    ancestors.each { |kind| return true if kind == klass }

    if error
      message = error.class == String ? error : %[Expected "#{self}" to be of "#{klass}"]
      raise ArgumentError.new(message)
    else
      false
    end
  end

  def andand func=nil
    if present?
      if block_given?
        yield(self)
      else
        func ? send(func) : self
      end
    else
      block_given? || func ? nil : {}.to_hwia
    end
  end

  def instance_variables_hash
    vars = instance_variables - [:@current]
    vars = vars.reject { |var| var[0,2] == '@_' }
    Hash[vars.map { |name| [name, instance_variable_get(name)] }]
  end

  # value should be Float
  # value.is! Float
  def is! value
    if value == self.class
      true
    else
      raise ArgumentError.new('Expected %s but got %s in %s' % [value, self.class, caller[0]])
    end
  end

  # value can be nil but if defined should be Float
  # value.is? Float
  def is? value
    is! value
  end
end

