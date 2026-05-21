# Lux::Environment - agent guide

Three independent facets.

## Canonical example

```ruby
Lux.env.production?     # name (dev/prod/test) - set by RACK_ENV/LUX_ENV
Lux.mode.log?           # behavior toggle - dev=on by default, override via LUX_LOG
Lux.runtime.web?        # process kind - derived from $PROGRAM_NAME

# typical use: gate behavior on the right facet
Lux::Reloader.run if Lux.mode.reload?
Lux.error.not_found Lux.mode.errors?('404') { 'detailed debug msg' }
Lux.cache.fetch_if_true('check', ttl: 60) { ... } unless Lux.env.test?
```

## Rules

* **`Lux.env`** = name (dev/prod/test). Set via `RACK_ENV` or `LUX_ENV`.
  Use for "is this prod?" decisions about side effects (real email,
  real payments, ...).
* **`Lux.mode`** = behavior toggles, independent from env. A prod box
  can run with `LUX_LOG=true` for diagnostics. Use for "should I be
  verbose / reload / show errors?".
* **`Lux.runtime`** = process kind. Use for "am I under a web server?"
  (don't write log to STDOUT if not web; don't run background sweepers
  in rake tasks; ...).
* **Block form of `Lux.mode.errors?`**: returns the string in prod,
  evaluates the block in dev. Use for dev-only verbose messages.

## Don't

* Conflate the three. "prod-style" log routing is `Lux.runtime.web? + Lux.env.prod?`,
  not just `Lux.env.prod?`.
* Use `RACK_ENV == 'production'` inline - go through `Lux.env.prod?`.
* Set `Lux.mode.log = true` permanently in code; use the env var so
  ops can flip it without redeploy.
* Forget that `Lux.env.development?` is true for **both** dev and test.
  Use `.dev?` if you specifically mean "not test, not prod".

## See also

* [`Lux::Config` AGENTS](../config/AGENTS.md)
* [`Lux::Reloader` AGENTS](../reloader/AGENTS.md)
