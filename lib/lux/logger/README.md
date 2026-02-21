## Lux.logger

Unified logging for the Lux framework.

### Default logger

`Lux.logger` returns a single `Logger` instance configured per environment:

- **Development**: logs to STDOUT at `:info` level, clean formatter (no timestamps)
- **Production**: logs to `./log/error.log` at `:error` level, standard formatter

```ruby
Lux.logger.info 'request processed'
Lux.logger.error 'something broke'
```

### Convenience shortcut

`Lux.log` is a shortcut for `Lux.logger.info`:

```ruby
Lux.log 'message'
Lux.log { 'lazy evaluated message' }
```

### Named file loggers

`Lux.logger(:name)` returns a named `Logger` writing to `./log/{name}.log` with rotation.
Available for app/plugin use.

```ruby
Lux.logger(:foo).info 'hello'  # writes to ./log/foo.log
```

### Configuration

```ruby
# Named logger settings
Lux.config.logger_path_mask     = './log/%s.log'  # path pattern
Lux.config.logger_files_to_keep = 3               # rotation count
Lux.config.logger_file_max_size = 10_240_000       # 10 MB per file
Lux.config.logger_formatter     = nil              # custom formatter for named loggers
```
