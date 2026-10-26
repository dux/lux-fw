module Lux
  class Router
    module Callbacks
      # A `before` filter that wrote the response ends its chain, so a later
      # filter cannot overwrite a 403 with its own redirect.
      HALTING_CALLBACKS ||= %i[before]

      # Overrides ClassCallbacks#run_callback: parent class first. `skip:` drops
      # every class and module in that class's ancestry - a mounted router passes
      # the mounting router's class, so hooks it already ran do not run twice.
      def run_callback name, *args, skip: nil
        ivar    = "@class_callbacks_#{name}"
        halting = HALTING_CALLBACKS.include?(name)
        list    = self.class.ancestors
        list    = list.slice 0, list.index(Object) if list.index(Object)
        list   -= skip.ancestors if skip

        list.reverse.each do |klass|
          next unless klass.instance_variable_defined?(ivar)

          klass.instance_variable_get(ivar).each_value do |m|
            m.is_a?(Array) ? m.each { send _1, *args } : instance_exec(*args, &m)
            return if halting && Lux.ctx.response.body?
          end
        end
      end
    end
  end
end
