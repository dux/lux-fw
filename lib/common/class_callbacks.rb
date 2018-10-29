# Rails style callbacks

# for controllers, execute from AppController to MainController
# class_callback :before
# before do
#    ...
# end
# before :method_name
# instance = new
# Object.class_callback :before, instance
# Object.class_callback :before, instance, arg

class Object
  def self.class_callback name, context=nil, arg=nil
    ivar = "@ccallbacks_#{name}"

    unless context
      define_singleton_method(name) do |method_name=nil, &block|
        ref = caller[0].split(':in ').first

        self.instance_variable_set(ivar, {}) unless instance_variable_defined?(ivar)
        self.instance_variable_get(ivar)[ref] = method_name || block
      end

    else
      list = context.class.ancestors
      list = list.slice 0, list.index(Object)

      list.reverse.each do |klass|
        if klass.instance_variable_defined?(ivar)
          mlist = klass.instance_variable_get(ivar).values
          mlist.each do |m|
            if m.class == Symbol
              context.send m
            else
              context.instance_exec arg, &m
            end
          end
        end
      end
    end
  end
end
