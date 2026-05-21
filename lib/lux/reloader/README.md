# Lux::Reloader

Custom code reloader. Skips installed gems via `Gem.path`, so reload is
fast even with a fat Gemfile. Reopens classes in place (`load`) so
existing class references stay valid.

## Small example

```ruby
Lux::Reloader.run        # reload anything modified since last check
```

## Full example

```ruby
# called automatically per-request in dev when both:
#   Lux.mode.reload?   (default in dev)
#   Lux.runtime.web?   (under a web server)

# CLI helper - reload from inside `bundle exec lux console`:
reload!

# scope:
# * watches $LOADED_FEATURES
# * skips files under Gem.path (any installed gem)
# * skips files containing /. (hidden)
# * triggers `load` on each modified file
# * runs Lux.config.on_reload_code block if defined

# Trade-off: methods removed from source linger until full restart
# (because `load` reopens; it doesn't undefine).
```

## When to use

* **Dev web requests:** automatic. No config needed.
* **Console reload:** `reload!` after editing files.
* **CI / scripts:** not needed - they run once.

## Notes

* `Lux.mode.reload?` toggles per-request reload. Off in prod, off in
  test, on in dev.
* Dev gems (`bundle config local.foo /path/to/foo` style) live outside
  `Gem.path` so they DO get reloaded - which is what you want.
* Reloading does not re-run `loader.rb` files - they boot once at
  startup. If your plugin's boot logic changed, restart the process.

## See also

* [`../environment/README.md`](../environment/README.md) - `Lux.mode.reload?`
* [`../config/README.md`](../config/README.md) - `on_reload_code` hook
* [`AGENTS.md`](./AGENTS.md) - LLM guide
