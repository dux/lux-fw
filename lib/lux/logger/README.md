# Lux::Logger

Unified logging. One default logger per environment plus named loggers
for app/plugin use, with rotation.

## Small example

```ruby
Lux.log 'request processed'         # shortcut: Lux.logger.info
Lux.log { 'lazy ' + expensive }     # block form, only built if level allows
Lux.logger.error 'boom'

Lux.logger(:audit).info 'user logged in'    # writes to ./log/audit.log
```

## Full example

```ruby
# --- default logger ---------------------------------------------------

Lux.logger.info  'ok'
Lux.logger.warn  'careful'
Lux.logger.error 'broken'
Lux.logger.debug 'details'         # only in dev/test

# Default: dev = STDOUT @ :info, prod = ./log/error.log @ :error

# --- named loggers ----------------------------------------------------

Lux.logger(:audit).info 'login'    # ./log/audit.log
Lux.logger(:email).info 'sent'     # ./log/email.log

# --- config -----------------------------------------------------------

Lux.config.logger_path_mask     = './log/%s.log'      # path pattern
Lux.config.logger_files_to_keep = 3                    # rotation count
Lux.config.logger_file_max_size = 10_240_000           # 10 MB per file

# Custom formatter for named loggers:
Lux.config.logger_formatter do |severity, datetime, progname, msg|
  msg = "#{severity}: #{msg}" if severity != 'INFO'
  "[#{datetime.utc}] #{msg}\n"
end

# Custom output destination:
Lux.config.logger_output_location do |name|
  Lux.env.prod? ? "./log/#{name}.log" : STDOUT
end
```

## Convention

* `Lux.log` for casual app logging - it's `Lux.logger.info` underneath.
  Block form is lazy - the string only builds if the log level allows.
* `Lux.logger.error` for actual errors.
* `Lux.logger(:name)` for anything you'd want a separate file for:
  audit trails, slow queries, outbound API calls, mailer events, ...

## See also

* [`../environment/README.md`](../environment/README.md) - dev / prod / test
* [`../config/README.md`](../config/README.md) - logger config hooks
* [`AGENTS.md`](./AGENTS.md) - LLM guide
