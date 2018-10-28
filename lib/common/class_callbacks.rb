# Rails style callbacks

class Object
  # for controllers, execute from AppController to MainController
  # class_callback :before
  # before do
  #    ...
  # end
  # instance = new
  # Object.class_callback :before, instance
  CLASS_CALLBACKS ||= {}
  def self.class_callback name, context=nil
    unless context
      define_singleton_method(name) do |&block|
        ref = caller[0].split(':in ').first

        CLASS_CALLBACKS[self.to_s]          ||= {}
        CLASS_CALLBACKS[self.to_s][name]    ||= {}
        CLASS_CALLBACKS[self.to_s][name][ref] = block
      end

    else
      list = context.class.ancestors.map(&:to_s)
      list = list.slice(0, list.index('Object'))

      list.reverse.each do |klass|
        mlist = CLASS_CALLBACKS.dig(klass, name).try(:values) || []
        mlist.each { |m| context.instance_exec &m }
      end
    end
  end
end

# strange bugs with this
# class Object
#   def self.class_callback name, context=nil
#     ivar = '@' + ['ccallbacks', name].join('_/').gsub(/[^\w]/, '_').downcase

#     unless context
#       define_singleton_method(name) do |&block|
#         ref = caller[0].split(':in ').first

#         self.instance_variable_set(ivar, {}) unless instance_variable_defined?(ivar)
#         self.instance_variable_get(ivar)[ref] = block
#       end

#     else
#       list = context.class.ancestors
#       list = list.slice 0, list.index(Object)

#       list.reverse.each do |klass|
#         if klass.instance_variable_defined?(ivar)
#           mlist = klass.instance_variable_get(ivar).values
#           mlist.each { |m| context.instance_exec &m }
#         end
#       end
#     end
#   end
# end
