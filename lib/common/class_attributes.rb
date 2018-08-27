# frozen_string_literal: true

# ClassAttributes.define klass, :layout, 'default_value_optional'
# klass.layout -> get value
# klass.layout = value -> set value

# class A
#   class_attribute :layout, 'default'
# end
# class B < A
#   layout 'l B'
# end
# class C < B
# end
# puts A.layout # default
# puts B.layout # l B
# puts C.layout # l B

module ClassAttributes
  extend self

  @@CA_DEFAULTS ||= {}

  # defines class variable
  def define klass, name, default=nil, &block
    raise ArgumentError, 'name must be symbol' unless name.class == Symbol

    # auto reload will define class methods again and overload runtime values
    return if klass.respond_to?(name)

    # store values uder
    @@CA_DEFAULTS[klass.to_s] ||= {}
    @@CA_DEFAULTS[klass.to_s][name] = { 'Object' => block || default }

    klass.define_singleton_method('%s=' % name) { |arg=:_nil| send name, arg }

    klass.define_singleton_method(name) do |arg=:_nil|
      # set and return if value defined
      if arg != :_nil
        @@CA_DEFAULTS[klass.to_s][name][self.to_s] = arg
        return arg
      end

      # find value and return
      ancestors.map(&:to_s).each do |el|
        value = @@CA_DEFAULTS[klass.to_s][name][el]

        if value || el == 'Object'
          value = instance_exec(&value) if value.is_a?(Proc)
          return value
        end
      end
    end
  end
end

def Object.class_attribute name, default=nil, &block
  ClassAttributes.define self, name, default, &block
end
