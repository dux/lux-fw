# frozen_string_literal: true

# in some class
# ClassCallbacks.define self, :before, :after
#
# then to execute
# instance_object = SomeClass.new
# ClassCallbacks.execute(instance_object, :before)
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
    key = Crypt.md5(unique_id)
    @@pointers[key] = method
    @@methods[klass.to_s] ||= {}
    @@methods[klass.to_s][action] ||= []
    @@methods[klass.to_s][action].push(key) unless @@methods[klass.to_s][action].index(key)
  end

  def execute instance_object, action, object=nil
    object ? instance_object.send(action, object) : instance_object.send(action)

    # execute for self and parent
    for name in instance_object.class.ancestors.reverse.map(&:to_s)
      next if name == 'Object'

      if @@methods[name] && @@methods[name][action]
        for el in @@methods[name][action].map { |o| @@pointers[o] }
          if el.kind_of?(Symbol)
            object ? instance_object.send(el, object) : instance_object.send(el)
          else
            object ? instance_object.instance_exec(object, &el) : instance_object.instance_exec(&el)
          end
        end
      end
    end
  end

  def define(klass, *args)
    for action in args
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
