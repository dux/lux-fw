# Lux.plugin (Lux::Plugin)

Loads a plugin from `plugins/<name>/` under the application root or the
framework root. Plugins are loaded explicitly:

```ruby
Lux.plugin :db
Lux.plugin :authcog
Lux.plugin :foo, :bar           # load several at once
```

Plugin search path:

1. `Lux.root/plugins/<name>/`
2. `Lux.fw_root/plugins/<name>/`

## Plugin layout

```
plugins/<name>/
  loader.rb     # OPTIONAL. Boot logic, required first.
  load/         # OPTIONAL. All *.rb auto-required after loader.rb.
  Hammerfile    # OPTIONAL. Single-file CLI tasks.
  hammer/       # OPTIONAL. *_hammer.rb CLI tasks (multi-file).
  mount/        # OPTIONAL. Files symlinked into the app by `lux mount`.
```

A plugin must have at least `loader.rb` or `load/`, otherwise it is
considered empty and `Lux.plugin :name` raises.

### Load order

1. `loader.rb` (if present)
2. `load/**/*.rb` via `Dir.require_all` - depth-first, shallower files
   sorted before deeper ones, alphabetical within a directory. Files
   named `*_spec.rb` and `*_hammer.rb` are skipped.

`Hammerfile` and `hammer/` are not loaded by `Lux.plugin`; the `lux` CLI
discovers them at startup so commands are visible without loading the
plugin at runtime.

### Folder semantics

* `loader.rb` - explicit entry. Use for things that must run before the
  rest of the plugin is loaded: registering hooks, setting config,
  booting subsystems, calling `require_relative` on supporting files
  that live outside `load/`.
* `load/` - everything in this directory is auto-required. Use for
  classes/modules that always need to be available the moment the
  plugin is loaded. Subdirectories are walked recursively.
* `Hammerfile` / `hammer/` - CLI tasks discovered by the `lux` command.
  Not required when the plugin is loaded at runtime.
* `mount/` - mirrors the application root. Running `lux mount` walks
  every leaf file under `mount/` and creates a relative symlink at the
  matching path in `Lux.root`. Use it for assets, initializers, or
  config templates a plugin needs to drop into the host app. Symlinks
  pointing at the same plugin/path but a different filesystem location
  (gem path drift between machines) are rewritten silently on the next
  `lux mount`. Foreign files at the destination are skipped with a
  warning - they are never overwritten. See `lux mount:list` and
  `lux mount:doctor` to inspect state, and `lux mount:remove NAME` to
  unlink everything a plugin owns.
* Anything else (`lib/`, `views/`, `spec/`, `assets/`, ...) is plain
  convention. The loader does nothing with it. Reference it from
  `loader.rb` (e.g. `require_relative 'lib/foo'`) if you want it
  available at runtime.

## Plugin API

```ruby
Lux.plugin                # => Lux::Plugin module
Lux.plugin :foo           # load plugin :foo, returns its descriptor
Lux.plugin.get(:foo)      # descriptor for an already-loaded plugin
Lux.plugin.loaded         # all loaded descriptors
Lux.plugin.keys           # names of loaded plugins
Lux.plugin.folders        # filesystem folders of loaded plugins
```

Each descriptor exposes `.name` and `.folder`.

## Preparing a plugin to be packaged as a gem

The folder layout is designed so any `plugins/<name>/` can be dropped
into a `lux-<name>` gem later with no code changes:

```
lux-foo/
  lux-foo.gemspec
  lib/lux-foo.rb        # tiny shim, requires the loader below
  plugin/               # current plugins/foo/ contents go here
    loader.rb
    load/
    hammer/
```

Resolution from a gem is not implemented yet - `Lux.plugin :foo` still
only looks at filesystem folders.
