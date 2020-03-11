# default event bus error handle
Lux.config.on_event_error do |error, name|
  Lux.logger(:event_bus).error '[%s] %s' % [name, error.message]
end

