# Lux::Reloader

Custom code reloader. Skips installed gems via `Gem.path`, so reload is
fast even with a fat Gemfile. Reopens classes in place (`load`) so
existing class references stay valid.

Called automatically per-request in dev when both `Lux.reload?` and
`Lux.runtime.web?` are true.

`Lux.reloader` is the shim for the module.

## Full example

```ruby
# --- manual / programmatic ---------------------------------------------

Lux.reloader.run              # reload anything modified since last check

# --- console (defined for `bundle exec lux console`) -------------------

reload!                       # equivalent inside the console session

# --- environment toggles -----------------------------------------------

Lux.reload?              # true in dev (default), false in prod / test
Lux.reload = false       # turn off at runtime
```

## Scope

* Runs before the app `before` callbacks, so filters see the saved code.
* One reload at a time (mutex) - concurrent puma threads wait.
* Registers autoloads for files added under `app/` since boot
  (`Lux::Root.autoload!`), so a new model works without a restart.
* Watches `$LOADED_FEATURES`.
* Skips files under any `Gem.path` entry (installed gems).
* Skips hidden files (paths containing `/.`).
* Triggers `load` on each modified file (`require` would no-op).

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

* [`../environment/README.md`](../environment/README.md) - `Lux.reload?`
