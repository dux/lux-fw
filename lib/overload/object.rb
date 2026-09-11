class Object
  # Boot safety net. Plugins reference app base classes (ApplicationModel and
  # friends) while loading, before config/app.rb eager-loads ./app. Resolve the
  # constant across every app root; fall through to the native NameError when
  # nothing matches, so the standard message and backtrace are kept.
  def self.const_missing name
    return super unless defined?(Lux) && Lux.respond_to?(:root)
    return Object.const_get(name) if Lux.root.autoload_const(name)

    super
  end

  ###

  # @foo.or(2)
  def or _or = nil, &block
    self.blank? || self == 0 ? (block ? block.call : _or) : self
  end

  def try *args, &block
    if self.class == NilClass
      nil
    elsif block_given?
      data = args.first.nil? ? self : self.send(*args)
      yield data
    else
      self.send(*args)
    end
  end

  def presence
    self.present? ? self : nil
  end

  def die desc=nil, exp_object=nil
    desc ||= 'died without desc'
    desc = '%s: %s' % [exp_object.class, desc] if exp_object
    puts desc.colorize(:red)
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
    !is_true?
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
      block_given? || func ? nil : {}.to_lux_hash
    end
  end

  def instance_variables_hash
    vars = instance_variables - [:@current]
    vars = vars.reject { |var| var[0,2] == '@_' }
    Hash[vars.map { |name| [name, instance_variable_get(name)] }]
  end

  # value should be Float
  # value.is! Float
  def is! value = :_nil
    if value == :_nil
      if self.present?
        self
      else
        raise ArgumentError.new('Expected not not empty value')
      end
    elsif value == self.class
      self
    else
      if self.class == Class && self.superclass != Object
        if self.ancestors.include?(value)
          self
        else
          raise ArgumentError.new('There is no %s in %s ancestors in %s' % [value, self, caller[0]])
        end
      else
        raise ArgumentError.new('Expected %s but got %s in %s' % [value, self.class, caller[0]])
      end
    end
  end

  # value can be nil but if defined should be Float
  # value.is? Float
  def is? value = nil
    is! value
    true
  rescue ArgumentError
    false
  end

  def in? collection
    collection.include?(self)
  end
  alias :inside? :in?
end

