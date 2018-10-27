class Object
  # for controllers, execute from AppController to MainController
  # class_callback_up :before
  # before do
  #    ...
  # end
  def self.class_callback_up name
    define_method(name) { |arg=nil| true }

    define_singleton_method(name) do |&block|
      define_method(name) do |arg=nil|
        if arg
          super(arg) if defined?(super)
          instance_exec arg, &block
        else
          super() if defined?(super)
          instance_exec &block
        end
      end
    end
  end

  # for errors, execute first from AppController to MainController
  # def self.class_callback_first name
  #   unless defined?(name)
  #     define_method(name) { |arg=nil| true }
  #   end

  #   define_singleton_method(name) do |&block|
  #     define_method(name) { |arg=nil| arg ? instance_exec(arg, &block) : instance_exec(&block) }
  #   end
  # end

  # A.routes { print 'R1 ' }
  # A.routes { print 'R2 ' }
  # A.routes { print 'R3 ' }
  # A.routes self
  # R1 R2 R3
  CALL_STACK ||= {}
  def self.class_callback_stack name
    self.define_singleton_method(name) do |context=nil, &block|
      if context
        for m in CALL_STACK[self.to_s][name].values
          context.instance_exec(&m)
        end

        return
      end

      from = caller[0].split(':in ').first

      CALL_STACK[self.to_s]     ||= {}
      CALL_STACK[self.to_s][name] ||= {}
      CALL_STACK[self.to_s][name][from] = block
    end
  end
end