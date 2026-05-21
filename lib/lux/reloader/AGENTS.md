# Lux::Reloader - agent guide

Code reloader for dev. Skips gems via `Gem.path` so reload is cheap even
with a fat Gemfile.

## Canonical example

```ruby
# auto: per-request in dev/web (Lux.mode.reload? && Lux.runtime.web?)
# manual:
Lux::Reloader.run
# console: reload! (defined for `bundle exec lux console`)
```

## Rules

* **Uses `load`, not `require`.** Reopens classes in place so cached
  class references (e.g. `Routes::CONTROLLER_CLASS_CACHE`) survive.
* **Methods removed from source linger** until process restart. Live
  with it; it's the price of keeping refs valid.
* **Gems are NOT reloaded.** Files under any `Gem.path` entry are
  skipped. User dev gems (`bundle config local.foo`) are outside
  `Gem.path` so they DO reload.
* **Hook:** `Lux.config.on_reload_code { ... }` runs after the file
  list is loaded. Use to invalidate caches, reset connections, etc.
* **`loader.rb` files of plugins** are NOT re-run. Restart for boot
  changes.

## Don't

* Add `Lux::Reloader.run` calls outside the dev-web path - it's
  expensive and noisy.
* Rely on reload for state cleanup - it doesn't reset globals,
  Thread.current, or DB pools. Use the `on_reload_code` hook explicitly.
* Reload in production. `Lux.mode.reload?` is off in prod and test by
  default; don't override.

## See also

* [`Lux::Environment` AGENTS](../environment/AGENTS.md)
* [`Lux::Config` AGENTS](../config/AGENTS.md) - `on_reload_code`
