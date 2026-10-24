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

    # ClassCallbacks#run_callback, except that a before / before_action filter
    # that wrote the response ends its chain, so a later filter cannot
    # overwrite a 403 with its own redirect.
    HALTING_CALLBACKS ||= %i[before before_action]

    def run_callback name, *args
      return super unless HALTING_CALLBACKS.include?(name)

      ivar = "@class_callbacks_#{name}"
      list = self.class.ancestors
      list = list.slice 0, list.index(Object) if list.index(Object)

      list.reverse.each do |klass|
        next unless klass.instance_variable_defined?(ivar)

        klass.instance_variable_get(ivar).each_value do |m|
          m.is_a?(Array) ? m.each { send _1, *args } : instance_exec(*args, &m)
          return if lux.response.body?
        end
      end
    end
  end
end
