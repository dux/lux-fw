# Lux::Plugin

Plugin loader. Looks under `Lux.root/plugins/<name>/` first, then
`Lux.fw_root/plugins/<name>/`.

## Small example

```ruby
Lux.plugin :db                       # load one
Lux.plugin :db, :authcog, :html      # several
```

## Canonical layout

```
plugins/<name>/
  loader.rb       # OPTIONAL. boot logic, required first
  load/           # OPTIONAL. *.rb auto-required after loader
  routes.rb       # OPTIONAL. routing DSL evaluated by `plugin_route :name`
  Hammerfile      # OPTIONAL. single-file CLI tasks
  hammer/         # OPTIONAL. multi-file CLI tasks (*_hammer.rb)
  mount/          # OPTIONAL. files symlinked into the app by `lux mount`
```

A plugin needs at least `loader.rb` or `load/`. Otherwise `Lux.plugin :x`
raises.

## Load order

1. `loader.rb` if present (use for hooks, config registration, ordering)
2. `load/**/*.rb` via `Dir.require_all` - depth-first, alphabetical;
   files matching `*_spec.rb` / `*_hammer.rb` are skipped

`Hammerfile` and `hammer/` are NOT loaded at runtime - the `lux` CLI
discovers them at startup so commands are visible without loading the
plugin.

## Full example

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

# host app routes:
Lux do
  plugin_route :favicon              # at root
  map 'admin' do
    plugin_route :authcog            # mounted under /admin
  end
end

# plugins/foo/Hammerfile (or hammer/*_hammer.rb) -- CLI tasks
task :foo do
  desc 'Run foo'
  proc { Foo.do_it }
end
```

## Folder semantics

| Folder | Auto-loaded? | Purpose |
|--------|--------------|---------|
| `loader.rb`  | yes, first | boot logic; required-before-load |
| `load/`      | yes        | classes/modules that must be ready when the plugin is loaded |
| `routes.rb`  | only via `plugin_route :name` | routing DSL body |
| `Hammerfile` | only by CLI | tasks for `lux <cmd>` |
| `hammer/`    | only by CLI | multi-file CLI tasks |
| `mount/`     | only by `lux mount` | files symlinked into the app |
| anything else | no | convention; `loader.rb` can `require_relative` if needed |

## Mount semantics (`mount/`)

`lux mount` walks every leaf file under `mount/` and creates a relative
symlink at the matching path in `Lux.root`. Use for assets, initializers,
or config templates a plugin needs to drop into the host app.

* Symlinks pointing at the same plugin/path but a different filesystem
  location (gem path drift across machines) are silently rewritten.
* Foreign files at the destination are skipped with a warning. Never
  overwritten.
* `lux mount:list` / `lux mount:doctor` to inspect, `lux mount:remove NAME`
  to unlink.

## API

```ruby
Lux.plugin                       # => Lux::Plugin module
Lux.plugin :foo                  # load; returns descriptor
Lux.plugin.get(:foo)             # descriptor for an already-loaded plugin
Lux.plugin.loaded                # all loaded descriptors
Lux.plugin.keys                  # names
Lux.plugin.folders               # filesystem folders
```

Each descriptor exposes `.name` and `.folder`.

## See also

* [`../application/README.md`](../application/README.md) - `plugin_route :name`
* [`AGENTS.md`](./AGENTS.md) - LLM guide
