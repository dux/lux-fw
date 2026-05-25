# Lux::Reloader

Custom code reloader. Skips installed gems via `Gem.path`, so reload is
fast even with a fat Gemfile. Reopens classes in place (`load`) so
existing class references stay valid.

Called automatically per-request in dev when both `Lux.mode.reload?` and
`Lux.runtime.web?` are true.

`Lux.reloader` is the shim for the module.

## Full example

```ruby
# --- manual / programmatic ---------------------------------------------

Lux.reloader.run              # reload anything modified since last check

# --- console (defined for `bundle exec lux console`) -------------------

reload!                       # equivalent inside the console session

# --- post-reload hook --------------------------------------------------

# In a plugin loader or config/initializers/lux.rb
Lux.config.on_reload_code do
  Lux.cache.delete('some/cache/key')   # invalidate things, reset connections
end

# --- environment toggles -----------------------------------------------

Lux.mode.reload?              # true in dev (default), false in prod / test
Lux.mode.reload = false       # turn off at runtime
```

## Scope

* Watches `$LOADED_FEATURES`.
* Skips files under any `Gem.path` entry (installed gems).
* Skips hidden files (paths containing `/.`).
* Triggers `load` on each modified file (`require` would no-op).
* Runs `Lux.config.on_reload_code` block if defined.

Methods removed from source linger until full restart (because `load`
reopens; it doesn't undefine). Live with it; it's the price of keeping
existing references valid.

## When to use

* **Dev web requests:** automatic. No config needed.
* **Console reload:** `reload!` after editing files.
* **CI / scripts:** not needed - they run once.

## Notes

* Dev gems (`bundle config local.foo /path/to/foo`) live outside `Gem.path`
  so they DO get reloaded.
* Reloading does not re-run `loader.rb` files - they boot once at startup.
  If your plugin's boot logic changed, restart the process.

## See also

* [`../environment/README.md`](../environment/README.md) - `Lux.mode.reload?`
* [`../boot/config/README.md`](../boot/config/README.md) - `on_reload_code` hook
