# Lux::Plugin - agent guide

Plugin loader. Canonical folder layout enforces what gets auto-loaded
when.

## Canonical layout

```
plugins/<name>/
  loader.rb       # OPTIONAL. boot logic, required first
  load/           # OPTIONAL. *.rb auto-required after loader
  routes.rb       # OPTIONAL. routing DSL, evaluated via `plugin_route :name` or `plugin_routes`
  Hammerfile      # OPTIONAL. single-file CLI tasks
  hammer/         # OPTIONAL. multi-file CLI tasks (*_hammer.rb)
  mount/          # OPTIONAL. files symlinked into the app by `lux mount`
```

## Rules

* **At least `loader.rb` or `load/` is required.** Empty plugin =
  `Lux.plugin :x` raises.
* **`loader.rb` runs first.** Use for: registering hooks, ordering
  control, requiring files outside `load/` (e.g. `lib/`), setting
  config. Don't put plain class defs here that could go in `load/`.
* **`load/`** is auto-required depth-first, alphabetical. Files
  matching `*_spec.rb` / `*_hammer.rb` are skipped.
* **`routes.rb`** is evaluated only when the host app calls
  `plugin_route :name` (explicit, one plugin) or `plugin_routes` (loops
  every loaded plugin and evaluates each one's `routes.rb` if present).
  Not loaded automatically. Order and namespacing are the app's job.
* Auto-mount convention for `plugin_routes`: the plugin's `routes.rb`
  routes its Rack class with `map`, by convention
  `map '/admin/plugins/<name>' => LuxFooWeb`. Host app puts a single
  `plugin_routes` call at the bottom of its routes block.
* **`Hammerfile` / `hammer/`** are NOT loaded at runtime - they're
  picked up by the `lux` CLI at startup so commands appear in `lux help`
  without the plugin being active.
* **`mount/`** mirrors the app root. `lux mount` walks it and creates
  relative symlinks into `Lux.root`. Use for assets, config templates,
  initializers a plugin needs to drop in.
* **Anything else** (`lib/`, `views/`, `spec/`, `assets/`) is plain
  convention - the loader does nothing with it. Reference from `loader.rb`
  if you need it.

## When adding a new plugin

* Put boot logic in `loader.rb`.
* Put always-on classes in `load/`.
* Put CLI commands under `hammer/` (one file per command).
* Put route bindings in `routes.rb`. For plugins that should auto-mount
  (admin dashboards etc.), declare the full path inside -
  `map '/admin/plugins/<name>' => LuxFooWeb` - and tell the host app to
  call `plugin_routes`. For plugins that need host-controlled mount
  position, document `plugin_route :name` instead.
* If users need to drop config / templates into their app, put them in
  `mount/`. Tell them to run `lux mount`.

## Don't

* Put class definitions in `loader.rb` if they'd work in `load/` - the
  former runs once, the latter is auto-discovered.
* Auto-include `routes.rb` at framework boot - it must be opt-in via
  `plugin_route` (single) or `plugin_routes` (all-with-routes.rb) so the
  host app controls when and where plugin routes get evaluated.
* Bypass `Lux.plugin` with `require './plugins/foo/whatever'` - boot
  order matters; `Lux.plugin` ensures `loader.rb` runs first.

## See also

* [`Lux::Application` AGENTS](../application/AGENTS.md) - `plugin_route`, `plugin_routes`
