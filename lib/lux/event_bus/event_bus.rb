# EventBus.on('test') { |arg| puts 'jedan: %s' % arg }
# EventBus.on('test') { |arg| puts 'dva: %s' % arg }
# EventBus.on('test') { |arg| raise 'abc' }
# EventBus.call 'test', 'xxx'

module Lux::EventBus
  extend self

  EVENTS = {}

  def on name, key=nil, &proc
    key ||= caller[0].split(':in ').first.gsub(/[^\w]/,'')

    EVENTS[name] ||= {}
    EVENTS[name][key] ||= proc
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
