# @foo = :bar
# ivar.foo -> :bar
# ivar.baz -> ArgumentError

class IvarsProxy
  def initialize scope
    @scope = scope
  end

  def method_missing name
    ivar = @scope.instance_variable_get("@#{name}")
    raise ArgumentError.new('Instance varaible @%s not defiend' % name) if ivar.nil?
    ivar
  end
end

class Object
  def ivar
    @__ivars ||= IvarsProxy.new(self)
  end
end