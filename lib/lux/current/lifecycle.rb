module Lux
  module Lifecycle
    define_method(:current)  { Lux.current }
    define_method(:request)  { lux.request }
    define_method(:response) { lux.response }
    define_method(:params)   { lux.params }
    define_method(:nav)      { lux.nav }
    define_method(:session)  { lux.session }
    define_method(:user)     { lux.user }

    define_method(:redirect_to) { |where, flash = {}| lux.response.redirect_to where, flash }

    # A `before` filter that wrote the response ends its chain, so a later
    # filter cannot overwrite a 403 with its own redirect.
    HALTING_CALLBACKS ||= %i[before]

    # ClassCallbacks#run_callback, parent class first. `skip:` drops every
    # class and module in that class's ancestry - a mounted router passes the
    # mounting router's class, so hooks it already ran do not run twice.
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
          return if halting && lux.response.body?
        end
      end
    end
  end
end
