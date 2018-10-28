# Defines class variable

def Object.class_attribute name, default=nil, &block
  raise ArgumentError.new('name must be symbol') unless name.class == Symbol

  ivar = "@cattr_#{name}"
  instance_variable_set ivar, block || default

  define_singleton_method(name) do |arg=:_undefined|
    # define and set if argument given
    if arg != :_undefined
      instance_variable_set ivar, arg
    end

    # find value and return
    ancestors.each do |klass|
      if klass.instance_variable_defined?(ivar)
        value = klass.instance_variable_get ivar
        return value.is_a?(Proc) ? instance_exec(&value) : value
      end
    end
  end
end

# class A
#   class_attribute :layout, 'default'
#   class_attribute(:time) { Time.now }
# end

# class B < A
#   layout 'main'
# end

# class C < B
#   time '11:55'
# end

# for func in [:layout, :time]
#   for klass in [A, B, C]
#     puts "> %s = %s" % ["#{klass}.#{func}".ljust(8), klass.send(func)]
#   end
# end

# # > A.layout = default
# # > B.layout = main
# # > C.layout = main
# # > A.time   = 2018-10-28 18:07:33 +0100
# # > B.time   = 2018-10-28 18:07:33 +0100
# # > C.time   = 11:55
