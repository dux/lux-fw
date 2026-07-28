# Lux::Environment

Three orthogonal facets of "where am I running?":

* `Lux.env`     - environment name (`development`, `production`, `test`)
* `Lux.debug?` / `Lux.reload?` / `Lux.silent` - behavior toggles
* `Lux.runtime` - process kind (`web?`, `cli?`, `rake?`)

The toggles live flat on `Lux` because there are only ever three of them.
`Lux::Environment::Flags` is the object behind them (`Lux.flags`); it holds
the precedence and validation logic and is what the specs construct directly.

## Full example

```ruby
# --- Lux.env: name of the environment -----------------------------------

Lux.env                  # Lux::Environment instance, stringifies to env name
Lux.env.to_s             # 'development' / 'production' / 'test'
Lux.env.production?      # true only in production
Lux.env.development?     # NOT production (includes test)
Lux.env.test?            # only in test
Lux.env.prod?            # alias for production?
Lux.env.dev?             # alias for development?
Lux.env == :prod         # accepts :dev / :prod / :test and strings
Lux.env(:prod)           # same: Lux.env(:prod) -> bool
Lux.env.fibers?          # fiber-based server (falcon / any Fiber.scheduler)

# Set via LUX_ENV. Defaults to 'development'.

# --- behavior toggles ---------------------------------------------------

# Defaults per env:
#   dev:  debug=on  reload=on
#   prod: debug=off reload=off
#   test: debug=off reload=off

Lux.debug?          # verbose responses, pretty JSON, :info log level
Lux.reload?         # per-request code reload

# Block form for env-conditioned messages:
Lux.error.not_found Lux.debug?('404 Not Found') { 'long debug msg' }

# Runtime override (also via LUX_DEBUG / LUX_RELOAD env vars):
Lux.debug  = true
Lux.reload = false

# --- Lux.silent: mute framework chatter ---------------------------------

# Gates Lux.shell.info status lines and the per-statement DB SQL log.
# Errors, Lux.shell.die and an app's own puts still print.

Lux.silent               # => current state (bool)
Lux.silent true          # set persistently (false restores)
Lux.silent { ... }       # mute for the block, then restore previous
Lux.silent(false) { }    # un-mute for the block, then restore

# --- Lux.runtime: how the process was started ---------------------------

Lux.runtime.web?         # puma / falcon / rackup
Lux.runtime.cli?         # otherwise (no Rack::Handler)
Lux.runtime.rake?        # run via rake
```

## Notes

* `LUX_DEBUG`, `LUX_RELOAD` accept `true`/`false`
  (case-insensitive). Empty = unset. Other = boot-time error.
* `lux server` accepts `-d`, `-e`, `-r` flags for these on the CLI. It only
  ever forces a flag *off* - turning one on is left to the per-env default.
* `Lux.silent` is deliberately not one of the `FLAGS`: it is block-scoped,
  has no per-env default and no env var.
* `.env` is loaded during `Lux.boot!`, after anything that logged early may
  already have read the flags, so boot calls `Lux.flags.reload_env!` to
  re-read `LUX_DEBUG` / `LUX_RELOAD`. Runtime overrides survive that.
* `Lux.env.fibers?` is true under the falcon binary or when the current
  thread has a `Fiber.scheduler`. The framework uses it to key Sequel
  connections by fiber, widen the DB pool, and skip the per-request
  `Timeout` wrapper (thread-raise based, unsafe across fibers).

## See also

* [`../boot/config/README.md`](../boot/config/README.md) - app config + `.env`
