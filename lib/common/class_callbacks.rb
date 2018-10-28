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
      list = []
      context.class.ancestors.map(&:to_s).each do |o|
        break if o == 'Object'
        list.push o
      end

      list.reverse.each do |klass|
        mlist = CLASS_CALLBACKS.dig(klass, name).try(:values) || []
        mlist.each { |m| context.instance_exec &m }
      end
    end
  end
end
