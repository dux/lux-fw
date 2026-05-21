# Lux::Logger - agent guide

Unified logging.

## Canonical example

```ruby
# default logger (dev = STDOUT info, prod = ./log/error.log error)
Lux.log 'request handled'              # info-level shortcut
Lux.log { 'lazy ' + expensive_thing }  # block form, lazy build
Lux.logger.error 'boom'

# named loggers - separate files
Lux.logger(:audit).info 'user logged in'    # ./log/audit.log
Lux.logger(:email).info "sent #{mail.subject}"
```

## Rules

* **`Lux.log` is `Lux.logger.info` shortcut.** Prefer it for casual app
  logging. Use block form for anything non-trivial to build - the
  framework skips the build when the level is below threshold.
* **Named loggers** (`Lux.logger(:name)`) write to `./log/<name>.log`
  with rotation (`logger_files_to_keep` × `logger_file_max_size`).
* **For errors that should also surface to humans** (Sentry / Honeybadger
  / Slack), wire that in `Lux.config.on_logger_error` or via your error
  reporter; don't sprinkle calls in controllers.
* **Per-request screen logging** is controlled by `Lux.mode.log?`
  (separate from `Lux.logger`). `LOG()` global writes to `./log/LOG.log`
  for ad-hoc dumps from anywhere.

## Don't

* Use `puts` in controllers / models / jobs. Use the logger.
* Build expensive strings outside the block form when the log level
  might suppress them.
* Log secrets / PII without thought - logs are usually less protected
  than DB.

## See also

* [`Lux::Environment` AGENTS](../environment/AGENTS.md) - `Lux.mode.log?`
* [`Lux::Config` AGENTS](../config/AGENTS.md) - logger hooks
