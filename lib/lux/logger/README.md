## Lux.logger

Lux logger is logging helper module.

It has 2 basic methods, get pointer to a logger `Lux.logger(:name).info msg` and log to screen `Lux.log msg`

Uses default [Ruby logger](https://ruby-doc.org/stdlib/libdoc/logger/rdoc/Logger.html)

### Options

#### Lux.config.logger_path_mask

Defaults to `./log/%s.log`.

#### Lux.config.logger_formatter

If defined it will be assigned to all logs created by `Lux#logger`

#### Lux.config.logger_default

Default system logger output location called via `Lux#log`.

Defauls to `STDOUT` in development and `nil` in production (no render output log)

#### Lux.config.logger_files_to_keep = 3

By default keep 3 log files

#### Lux.config.logger_file_max_size = 10_240_000

10 MB per file log file

### Defaults and example

```ruby
# defaults
Lux.config.logger_path_mask     = './tmp/%s.log'
Lux.config.logger_default       = Lux.env.dev? ? STDOUT : nil
Lux.config.logger_files_to_keep = 3
Lux.config.logger_file_max_size = 10_240_000

# example
# by default writes in ./log/%s.log, log rotation 3 files, 10 MB each.
Lux.logger(:foo).info 'hello'
```
