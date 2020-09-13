# Lux.event.on('test') { |arg| puts 'one %s' % arg }
# Lux.event.on('test') { |arg| puts 'two: %s' % arg }
# Lux.event.on('test') { |arg| raise 'foo' }
# Lux.event.call 'test', 'abc'

module Lux
  module EventBus
    extend self

    EVENTS = {}

    def on name, key=nil, &block
      key ||= caller[0].split(':in ').first.gsub(/[^\w]/,'')

      EVENTS[name]      ||= {}
      EVENTS[name][key] ||= block
    end

    def call name, opts=nil
      for func in EVENTS[name].values
        begin
          func.call opts
        rescue => error
          Lux.config.on_event_bus_error.call error, name
        end
      end
    end
  end
end
