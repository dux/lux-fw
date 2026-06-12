# Lux::Logger

Unified logging. One default logger per environment plus named loggers
for app/plugin use, with rotation.

`Lux.log` is the casual shortcut (`Lux.logger.info` underneath, with a
lazy block form). `Lux.logger(:name)` returns a named per-file logger.

## Full example

```ruby
# --- default logger ---------------------------------------------------

Lux.logger.info  'ok'
Lux.logger.warn  'careful'
Lux.logger.error 'broken'
Lux.logger.debug 'details'

# Default destination: dev = STDERR @ :info, test = IO::NULL, prod = ./log/error.log @ :error.
# Set log level via Lux.config.log_level (:info / :error).

# --- casual logging ---------------------------------------------------

Lux.log 'request processed'             # equivalent to Lux.logger.info
Lux.log { 'lazy ' + expensive_string }  # block only evaluated if level allows

# When LOG() has been called this request, screen logs are suppressed so
# only the LOG output is visible.

# --- named loggers (one file each) ------------------------------------

Lux.logger(:audit).info 'login'         # ./log/audit.log
Lux.logger(:email).info 'sent'          # ./log/email.log
Lux.logger(:slow).warn  '120ms'         # any name works; created on first use

# --- config (typically in ./config/initializers/lux.rb) --------------

Lux.config.logger_path_mask     = './log/%s.log'      # path pattern for named loggers
Lux.config.logger_files_to_keep = 3                    # rotation count
Lux.config.logger_file_max_size = 10_240_000           # 10 MB per file

# Custom formatter for named loggers:
Lux.config.logger_formatter do |severity, datetime, progname, msg|
  msg = "#{severity}: #{msg}" if severity != 'INFO'
  "[#{datetime.utc}] #{msg}\n"
end

# Custom output destination per logger:
Lux.config.logger_output_location do |name|
  Lux.env.prod? ? "./log/#{name}.log" : STDOUT
end
```

## Convention

* `Lux.log` for casual app logging - lazy block form avoids work in prod
  where the level might drop the message.
* `Lux.logger.error` for actual errors.
* `Lux.logger(:name)` for anything you'd want a separate file for:
  audit trails, slow queries, outbound API calls, mailer events, ...

## See also

* [`../environment/README.md`](../environment/README.md) - dev / prod / test
* [`../boot/config/README.md`](../boot/config/README.md) - logger config hooks
