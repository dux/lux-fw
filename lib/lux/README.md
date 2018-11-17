## Page render flow

### Example config.ru
```
$lux_start_time = Time.now
require './config/application'
Lux.serve self
```

* if you define `$lux_start_time` you will get speed load statistics
