## Page render flow

### Example config.ru
```ruby
$lux_start_time = Time.now
require_relative 'config/application'
Lux.serve self
```

* if you define `$lux_start_time` you will get speed load statistics
