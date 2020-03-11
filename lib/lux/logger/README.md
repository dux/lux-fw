## Lux.logger

Lux logger is logging helper module.

* uses default [Ruby logger](https://ruby-doc.org/stdlib/libdoc/logger/rdoc/Logger.html)
* logger output path/location can be customized via `Lux.config.logger_output_location` proc
  * default outputs
    * development: screen
    * production: `./log/@name.log`
* formating style can be customized by modifing `Lux.config.logger_formater`
* logger defined via the name will be created unless exists

```ruby
##./lib/lux/config/defaults/logger.rb##

Lux.logger(:foo).info 'hello' # ./log/foo.log

# write allways to file and provide env sufix
Lux.config.logger_output_location do |name|
  './log/%s-%s.log' % [name, Lux.env]
end

Lux.logger(:bar).info 'hello' # ./log/bar-development.log
```
