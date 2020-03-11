## Lux.event (Lux::EventBus)

Super simple event pub/sub

```ruby
Lux.event.on('test') { |arg| puts 'foo: %s' % arg }
Lux.event.on('test', :foo) { |arg| puts 'bar: %s' % arg }
Lux.event.on('test', :foo) { |arg| puts 'baz: %s' % arg

# to call
Lux.event.call 'test', 'xxx'
```
