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
    is_a?(::Hash) || self.class.name&.end_with?('Hash') || false
  end

  def is_array?
    is_a?(::Array) || self.class.name&.end_with?('Array') || false
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
      return self if present?
      raise ArgumentError, 'Expected a non-empty value'
    end

    ok = value.is_a?(Module) && (is_a?(value) || (is_a?(Module) && self <= value))
    return self if ok
    raise ArgumentError, 'Expected %s but got %s in %s' % [value, is_a?(Module) ? self : self.class, caller[0]]
  end

  def in? collection
    collection.include?(self)
  end
end

