# Lux::Plugin

Plugin loader. Looks under `Lux.root/plugins/<name>/` first, then
`Lux.fw_root/plugins/<name>/`.

`Lux.plugin(*names)` loads plugins; `Lux.plugin` (no args) returns the
`Lux::Plugin` module for introspection.

## Full example

```ruby
# --- loading ---------------------------------------------------------

Lux.plugin :db                      # load one
Lux.plugin :db, :authcog, :html     # several

# --- introspection ---------------------------------------------------

Lux.plugin                          # the Lux::Plugin module itself
Lux.plugin.get(:foo)                # descriptor for an already-loaded plugin
Lux.plugin.loaded                   # all loaded descriptors
Lux.plugin.keys                     # names
Lux.plugin.folders                  # filesystem folders
```

Each descriptor exposes `.name` and `.folder`.
A plugin with a `mount/` folder has that folder registered as a `Lux::Root`
overlay root on load, so its files resolve in place:

```ruby
Lux.root.path 'app/views/foo.haml'   # walks the app root, then plugin mounts
Lux.root.file 'rollup.config.js'     # raises Lux::Root::NotFound when missing
```

Subsystems that want to attach their own per-plugin behavior can push a module
into `Lux::Plugin::DESCRIPTOR_MIXINS`; every loaded descriptor is `extend`ed
with each registered mixin.

## Canonical layout

```
plugins/<name>/
  config.yaml     # OPTIONAL. merged into Lux.config before loader.rb
  loader.rb       # OPTIONAL. boot logic, required before load/
  load/           # OPTIONAL. *.rb auto-required after loader
  routes.rb       # OPTIONAL. routing DSL evaluated by plugin_route :name / plugin_routes
  Hammerfile      # OPTIONAL. single-file CLI tasks
  hammer/         # OPTIONAL. multi-file CLI tasks (*_hammer.rb)
  mount/          # OPTIONAL. mirrors app root; registered as a Lux::Root overlay
```

A plugin needs at least `config.yaml`, `loader.rb`, or `load/`. Otherwise
`Lux.plugin :x` raises.

## Load order

1. `config.yaml` if present - merged into `Lux.config`; a top-level
   `plugins:` list appends to the configured plugin list
2. `loader.rb` if present (use for hooks, config registration, ordering)
3. `load/**/*.rb` via `Dir.require_all` - depth-first, alphabetical;
   files matching `*_spec.rb` / `*_hammer.rb` are skipped

`Hammerfile` and `hammer/` are NOT loaded at runtime - the `lux` CLI
discovers them at startup so commands are visible without loading the
plugin.

## Authoring a plugin

```yaml
# plugins/foo/config.yaml -- merged before loader.rb
default:
  foo:
    enabled: true

plugins:
  - bar                              # plugin dependency; appended to plugin list
```

```ruby
# plugins/foo/loader.rb -- explicit entry, runs before load/
require_relative 'lib/some_low_level_thing'

Lux.config.on_reload_code do
  # ...
end

# plugins/foo/load/foo.rb -- auto-required
class Foo
  def self.do_it; ...; end
end

# plugins/foo/routes.rb -- evaluated when host app calls plugin_route :foo
map 'foo' => 'foo#root'
map 'foo/widgets'

# plugins/foo/Hammerfile -- CLI tasks
task :foo do
  desc 'Run foo'
  proc { Foo.do_it }
end
```

In the host:

```ruby
Lux do
  routes do
    plugin_route :web_common           # explicit, at root
    map 'admin' do
      plugin_route :my_plugin          # explicit, mounted under /admin
    end

    plugin_routes                      # loops every loaded plugin with routes.rb;
                                       # convention: /admin/plugins/<name>
  end
end
```

## Folder semantics

| Folder | Auto-loaded? | Purpose |
|--------|--------------|---------|
| `config.yaml` | merged first | plugin defaults; `plugins:` entries append to configured plugins |
| `loader.rb`  | yes, after config | boot logic; required-before-load |
| `load/`      | yes        | classes/modules that must be ready when the plugin is loaded |
| `routes.rb`  | only via `plugin_route :name` or `plugin_routes` | routing DSL body |
| `Hammerfile` | only by CLI | tasks for `lux <cmd>` |
| `hammer/`    | only by CLI | multi-file CLI tasks |
| `mount/`     | registered on load | mirrors app root; resolved through Lux::Root |

## Mount semantics (`mount/`)

A plugin's `mount/` folder mirrors the app root.
On load it is appended to `Lux::Root`, the ordered overlay the framework
resolves app paths against.
Files are used in place - nothing is copied or symlinked into the host app.

* The app root comes first, so an app file shadows a plugin file with no
  special handling.
* `Lux.root.path` / `.file` / `.lib` resolve across every root and raise
  `Lux::Root::NotFound` naming each location tried.
* The same roots feed eager loading (`Lux.root.require_all 'app'`), template
  lookup and the asset pipeline.
* Node build files (`rollup.config.js`) cannot read `Lux::Root`, so
  `lux assets:auto` materializes the first one found into the app root.

## See also

* [`../application/README.md`](../application/README.md) - `plugin_route :name`, `plugin_routes`
