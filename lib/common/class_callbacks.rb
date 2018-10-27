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
          super(arg)
          instance_exec arg, &block
        else
          super()
          instance_exec &block
        end
      end
    end
  end

  # for errors, execute first from AppController to MainController
  def self.class_callback_first name
    define_method(name) { true }

    define_singleton_method(name) do |&block|
      define_method(name) { |arg=nil| arg ? instance_exec(arg, &block) : instance_exec(&block) }
    end
  end

  # A.routes { print 'R1 ' }
  # A.routes { print 'R2 ' }
  # A.routes { print 'R3 ' }
  # A.routes self
  # R1 R2 R3
  CALL_STACK       ||= {}
  CALL_STACK_CHECK ||= []
  def self.class_callback_stack name
    self.define_singleton_method(name) do |context=nil, &block|
      return CALL_STACK[name].each { |m| context.instance_exec(&m) } if context

      from = caller[0].split(':in ').first
      return if CALL_STACK_CHECK.include?(from)
      CALL_STACK_CHECK.push(from)

      CALL_STACK[name] ||= []
      CALL_STACK[name].push block
    end
  end
end