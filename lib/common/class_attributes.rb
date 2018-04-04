# frozen_string_literal: true

# ClassAttributes.define klass, :layout, 'default_value_optional'
# klass.layout -> get value
# klass.layout = value -> set value

# class A
#   ClassAttributes.define self, :layout, 'default'
# end
# class B < A
#   layout 'l B'
# end
# class C < B
# end
# puts A.layout # default
# puts B.layout # l B
# puts C.layout # l B

# class User
#   ClassAttributes.define_in_current_thread self, :current
# end

# User.current = User.first

module ClassAttributes
  extend self

  CA_DEFAULTS = {}

  # defines class variable
  def define klass, name, default=nil, &block
    raise ArgumentError, 'name must be symbol' unless name.class == Symbol

    default ||= block if block

    ::ClassAttributes::CA_DEFAULTS[name] = { 'Object'=>default }

    klass.define_singleton_method('%s=' % name) { |*args| send name, *args}
    klass.define_singleton_method(name) do |*args|
      root = ::ClassAttributes::CA_DEFAULTS[name]

      # set and return if argument defined
      return root[to_s] = args[0] if args.length > 0

      # find value and return
      ancestors.map(&:to_s).each do |el|
        value = root[el]
        if value || el == 'Object'
          value = instance_exec(&value) if value.is_a?(Proc)
          return value
        end
      end
    end
  end

  # defines class variable in current lux thread
  # User.current = @user
  # def current klass, name
  #   klass.class.send(:define_method, name) do |*args|
  #     Thread.current[:lux] ||= {}
  #     Thread.current[:lux]['%s-%s' % [klass, name]]
  #   end

  #   klass.class.send(:define_method, '%s=' % name) do |value|
  #     Thread.current[:lux] ||= {}
  #     Thread.current[:lux]['%s-%s' % [klass, name]] = value
  #   end
  # end
end

class Object
  def class_attribute name, default=nil, &block
    ClassAttributes.define self, name, default, &block
  end
end