## Lux.env (Lux::Environment)

Module provides access to environment settings.

```ruby
Lux.env.development? # true in development and test
Lux.env.production?  # true in production and log
Lux.env.test?        # true for test
Lux.env.log?         # true for log
Lux.env.rake?        # true if run in rake
Lux.env.cli?         # true if not run under web server

# aliases
Lux.env.dev?  # Lux.env.development?
Lux.env.prod? # Lux.env.production?
```

Lux provides only 4 environent modes that are set via `ENV['RACK_ENV']` settings -
  `development`, `production`, `test` and `log`.
  * `test` and `log` are special modes
    * `test`: will retun true to `Lux.env.test?` and `Lux.env.develoment?`
    * `log`: Production mode with output logging. It will retun true for
      `Lux.env.log?` and `Lux.env.production?` or `Lux.env.prod?`.
      This mode is activated if you run server with `bundle exec lux ss`
