# Super simple event pub/sub

## to add events

```ruby
  Lux::EventBus.on('test') { |arg| puts 'foo: %s' % arg }
  Lux.event.on('test', :foo) { |arg| puts 'bar: %s' % arg }
  Lux.event.on('test', :foo) { |arg| puts 'baz: %s' % arg }
  Lux.event.on('test') { |arg| raise 'abc' }

  ###
  # foo: xxx
  # baz: xxx
  # error logged
```


## to call

```ruby
  Lux.event.call 'test', 'xxx'
```


## Error handler

Default event bus error handle.

```ruby
  Lux.config.on_event_bus_error = proc do |error, name|
    Lux.logger(:event_bus).error '[%s] %s' % [name, error.message]
  end
```



