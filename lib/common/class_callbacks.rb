# Rails style callbacks

# for controllers, execute from AppController to MainController
# class_callback :before
# before do
#    ...
# end
# before :method_name
# instance = new
# instance.class_callback :before,
# instance.class_callback :before, arg

class Object
  def class_callback name, arg=nil
    Object.class_callback name, self, arg
  end

  def self.class_callback name, context=nil, arg=nil
    ivar = "@ccallbacks_#{name}"

    unless context
      define_singleton_method(name) do |method_name=nil, &block|
        ref = caller[0].split(':in ').first

        self.instance_variable_set(ivar, {}) unless instance_variable_defined?(ivar)
        self.instance_variable_get(ivar)[ref] = method_name || block
      end

    else
      list = context.respond_to?(:new) ? context.ancestors : context.class.ancestors
      list = list.slice 0, list.index(Object)

      list.reverse.each do |klass|
        if klass.instance_variable_defined?(ivar)
          mlist = klass.instance_variable_get(ivar).values
          mlist.each do |m|
            if m.is_a?(Symbol)
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
