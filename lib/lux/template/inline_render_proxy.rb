# enables variable access as a method call to render helper
# = render :_menu, foo: 123, bar: nil
# render.foo # 123
# render.bar ||= 456
# render.bar # 456
module Lux
  class InlineRenderProxy
    def initialize context, &block
      @context = context
      @block   = block
    end

    def method_missing name, value=nil
      name = name.to_s

      if name.sub!('=', '')
        @context.instance_variable_set("@_#{name}", value)
      end

      @context.instance_variable_get("@_#{name}")
    end
  end

  def [] name
    @context.instance_variable_get("@_#{name}")
  end

  def []= name, value
    @context.instance_variable_set("@_#{name}", value)
  end
end
