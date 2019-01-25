class Object

  def self.const_missing klass
    file  = klass.to_s.underscore
    paths = [
      'models',
      'lib',
      'lib/vendor',
      'vendor',
      file.split('_').last.pluralize
    ].map  { |it| './app/%s/%s.rb' % [it, file] }

    klass_file = paths.find { |it| File.exist?(it) } or
      raise NameError.new('Can not find and autoload class "%s", looked in %s' % [klass, paths.map{ |it| "\n#{it}" }.join('')])

    # puts '* autoload: %s from %s' % [file, klass_file]

    require klass_file

    Object.const_get(klass)
  end

  ###

  def or _or
    self.blank? || self == 0 ? _or : self
  end

  def try *args
    return nil if self.class == NilClass
    block_given? ? yield(self) : self.send(*args)
  end

  def die desc=nil, exp_object=nil
    desc ||= 'died without desc'
    desc = '%s: %s' % [exp_object.class, desc] if exp_object
    puts desc.red
    puts caller.slice(0, 10)
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

  def andand func=nil
    if present?
      if block_given?
        yield(self)
      else
        func ? send(func) : self
      end
    else
      block_given? || func ? nil : {}.h
    end
  end

  def instance_variables_hash
    Hash[instance_variables.map { |name| [name, instance_variable_get(name)] } ]
  end
end

