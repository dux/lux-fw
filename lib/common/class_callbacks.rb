# frozen_string_literal: true

# in some class
# class_callbacks :before, :after
#
# then to execute in instance_object
# class_callback :before
# class_callback :after
#
# before do
#   ...
# end
#
# logic is very simple, keep all pointers to all blocks in one class, resolve and execute as needed
# we keep methods and ponters in different hashes to allow hot reload while development

module ClassCallbacks
  extend self

  @@methods  = {}
  @@pointers = {}

  def add klass, unique_id, action, method
    klass = klass.to_s
    key   = Digest::SHA1.hexdigest(unique_id)

    @@pointers[key] = method

    @@methods[klass] ||= {}
    @@methods[klass][action] ||= []
    @@methods[klass][action].tap { |it| it.push(key) unless it.include?(key) }
  end

  def execute instance_object, action, object=nil
    object ? instance_object.send(action, object) : instance_object.send(action)

    # execute for self and parents
    instance_object.class.ancestors.reverse.map(&:to_s).each do |name|
      actions = @@methods.dig(name, action)

      next if !actions || name == 'Object'

      for el in actions.map { |o| @@pointers[o] }
        if el.kind_of?(Symbol)
          object ? instance_object.send(el, object) : instance_object.send(el)
        else
          object ? instance_object.instance_exec(object, &el) : instance_object.instance_exec(&el)
        end
      end
    end
  end

  def define klass, *args
    args.each do |action|
      klass.class_eval %[
        def #{action}(duck=nil)
        end

        def self.#{action}(proc=nil, &block)
          ClassCallbacks.add(self, caller[0], :#{action}, proc || block)
        end
      ]
    end
  end
end

Object.class_eval do
  def self.class_callbacks *args
    ClassCallbacks.define self, *args
  end

  def class_callback name, arg=nil
    ClassCallbacks.execute self, name, arg
  end
end


