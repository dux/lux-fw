class Object
  # @foo.or(2)
  def or _or = nil, &block
    self.blank? || self == 0 ? (block ? block.call : _or) : self
  end

  # ActiveSupport semantics: public_send when the receiver responds to the
  # method, nil otherwise; a bare block is yielded self. NilClass#try is nil.
  def try *args, &block
    if args.empty? && block
      block.arity.zero? ? instance_eval(&block) : yield(self)
    elsif respond_to?(args.first)
      public_send(*args, &block)
    end
  end

  def presence
    self.present? ? self : nil
  end

  # this will capture plain Hash and Hash With Indifferent Access
  def is_hash?
    self.class.to_s.index('Hash') ? true : false
  end

  def is_array?
    self.class.to_s.index('Array') ? true : false
  end

  def is_true?
    Lux::Utils::Boolean.parse(self) == true
  end

  def is_numeric?
    Float(self) != nil rescue false
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

  private

  def die desc=nil, exp_object=nil
    desc ||= 'died without desc'
    desc = '%s: %s' % [exp_object.class, desc] if exp_object
    puts desc.colorize(:red)
    puts caller.slice(0, 10)
    raise desc
  end
end

