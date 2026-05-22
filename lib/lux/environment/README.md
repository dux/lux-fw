# Lux::Environment

Three orthogonal facets of "where am I running?":

* `Lux.env`     - environment name (`development`, `production`, `test`)
* `Lux.mode`    - behavior toggles (`log?`, `errors?`, `reload?`)
* `Lux.runtime` - process kind (`web?`, `cli?`, `rake?`)

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

# Set via RACK_ENV or LUX_ENV. Defaults to 'development'.

# --- Lux.mode: behavior toggles -----------------------------------------

# Defaults per env:
#   dev:  log=on  errors=on  reload=on
#   prod: log=off errors=off reload=off
#   test: log=off errors=off reload=off

Lux.mode.log?            # screen dev log: Lux.log, SQL echo, pretty JSON
Lux.mode.errors?         # rich error pages, verbose 404s
Lux.mode.reload?         # per-request code reload

# Block form for env-conditioned messages:
Lux.error.not_found Lux.mode.errors?('404 Not Found') { 'long debug msg' }

# Runtime override (also via LUX_LOG / LUX_ERRORS / LUX_RELOAD env vars):
Lux.mode.log = true
Lux.mode.errors = false
Lux.mode.reload = false

# --- Lux.runtime: how the process was started ---------------------------

Lux.runtime.web?         # puma / falcon / rackup
Lux.runtime.cli?         # otherwise (no Rack::Handler)
Lux.runtime.rake?        # run via rake
```

## Notes

* `LUX_LOG`, `LUX_ERRORS`, `LUX_RELOAD` accept `true`/`false`
  (case-insensitive). Empty = unset. Other = boot-time error.
* `lux server` accepts `-l`, `-e`, `-r` flags for these on the CLI.

## See also

* [`../config/README.md`](../config/README.md) - app config + `.env`
* [`AGENTS.md`](./AGENTS.md) - LLM guide
