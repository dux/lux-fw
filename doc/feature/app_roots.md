> STATUS: PLANNED. Replace `lux mount` symlinks with `Lux::Root`, an ordered
> overlay of app roots that the framework resolves against directly.

## app_roots

Plugins ship files that must appear in the host app: controllers, views,
assets, config and root-level build files.
Today `lux mount` materializes that by symlinking every leaf file from
`plugins/<name>/mount/` into the app root, and hides the links in
`.git/info/exclude`.

The symlink layer is fragile.
`Lux::Root` replaces it with a first-class ordered list of app roots that
Ruby-side resolution searches, so plugin files are used in place and nothing
is copied or linked into the app.

### Why the symlinks exist

Lux resolves everything from a single root:

* `config/app.rb` - `Dir.require_all './app'` walks the app tree to load
  controllers and models.
* `Lux::Controller` - `template_root` defaults to `./app/views`, one path.
* `Lux::Assets` - scans `./app/assets/auto`.

A plugin file therefore has to physically exist under `./app` for the
framework to see it.

### Problems with the symlink approach

* `.git/info/exclude` is per-clone and untracked, so a fresh clone or CI must
  run `lux mount` before boot or controllers and views silently vanish.
* Relative link targets embed the gem checkout path; `mount.rb` carries a
  `:stale` status and a regex rewrite only to heal that drift.
* Symlinks are invisible to tools that do not follow them; `rsync -aL`,
  `NODE_PRESERVE_SYMLINKS=1` and grep `-L` are all workarounds.
* Two representations to reason about (link vs copy) plus `--clean`,
  `--git-rm`, `prune_orphans` and `doctor`.
* A real app file blocks the mount as `:local`, so overriding a plugin view
  means manually deleting the link.
* Symlinks are unreliable in Docker build contexts and on Windows.

### Design

`Lux::Root` subclasses `Pathname`.
`Lux.root` returns a `Lux::Root` instance, so `Lux.root.join` and
`Lux.root.to_s` keep working unchanged.
No new methods are added to the `Lux` module.

Roots are ordered, app root first, then each loaded plugin's `mount/`
appended in load order.
First root wins, so an app file shadows a plugin file with no special
handling.

```ruby
module Lux
  class Root < Pathname
    NotFound = Class.new(StandardError)

    class << self
      def roots = [Lux.root, *overlays]

      # silent primitive - nil when missing
      def resolve(rel)
        return Pathname.new(rel) if Pathname.new(rel).absolute?
        roots.map { _1.join(rel) }.find(&:exist?)
      end

      # finders - raise with every location tried
      def path(rel) = resolve(rel) || die_not_found(rel)
      def file(rel) = (p = path(rel)).file? ? p : die_not_found(rel, 'not a file')

      # loader - ruby lib, require it
      def lib(rel)
        p = file(rel.end_with?('.rb') ? rel : "#{rel}.rb")
        require p.to_s
        p
      end

      # enumeration - merged across roots, first root shadows
      def files(glob) = ...
      def dirs(rel)   = ...
    end

    def path(rel) = self.class.path(rel)
    def file(rel) = self.class.file(rel)
    def lib(rel)  = self.class.lib(rel)
  end
end
```

Failure names every location that was tried:

```
Lux::Root::NotFound: Lux.root.path("app/views/main/root.haml") not found.
Looked in:
  /Users/dux/dev/rudex/vibe/app/views/main/root.haml
  /Users/dux/dev/gems/lux-fw/plugins/web_common/mount/app/views/main/root.haml
```

Writes and unresolved paths still resolve to the real app path, so generated
output, `tmp`, `log`, `public` and `db` stay in one writable root.

Roots come only from plugins; there is no config knob.
The roots list is class-level state so the frozen `Lux.root` instance is not a
problem.

### The Node exception

`rollup.config.js` is consumed by Node, not Ruby, so `Lux::Root` cannot reach
it.
`lux assets:auto` resolves the config through `Lux::Root` and writes a real,
gitignored `Lux.root/rollup.config.js`.
`NODE_PRESERVE_SYMLINKS` stays for the `node_modules/fez` symlink.

### Object.const_missing

The `Object.const_missing` autoloader is removed.
Every starter already eager-loads with `Dir.require_all './app'`, and the
starter comment records why the autoloader is not enough: it never fires for a
constant looked up inside a module.

Concrete bugs in the current loader:

* keys by basename only, so files with the same basename silently collide.
* no namespace support, so `Foo::Bar` can never autoload.
* scans only `./app`, blind to plugin roots.
* one-shot scan that is never reset on reload.
* marks a file attempted before `require`, so a failed require is sticky.
* cwd-relative `require` that breaks with absolute gem paths.
* pollutes `Object` with three constants.

`Lux.root.require_all('app')` replaces it: roots-aware, deduped by relative
path, first root wins, skipping `_spec.rb` and `app/views`.

## Changes

### Core

* `lib/lux/root.rb` - new `Lux::Root`.
* `lib/lux/lux.rb` - `root` returns `Lux::Root`; `DEPLOY_ID` scans merged roots.
* `lib/lux/plugin/plugin.rb` - append `mount/` to `Lux::Root` on load.

### Require and autoload

* delete `Object.const_missing` from `lib/overload/object.rb`.
* `lib/overload/dir.rb` - roots-aware `Dir.require_all` or `Lux::Root#require_all`.
* `config/app.rb` and both starters - `Lux.root.require_all('app')`.
* `lib/lux/application/lib/routes.rb` - debug caller match across roots.

### Templates

* `lib/lux/controller/controller.rb`.
* `lib/lux/controller/auto_controller.rb`.
* `lib/lux/template/template.rb` and `lib/lux/template/helper.rb`.
* `lib/lux/mail/sender.rb`.
* `lib/lux/view_cell/instance.rb` and `lib/lux/view_cell/view_cell.rb`.
* `plugins/locale/load/locale.rb`.

### Assets

* `bin/cli/assets_hammer.rb` - `auto_assets`, `get_files`, generator scan.
* `plugins/web_common/load/assets/cdn_asset.rb` - merged glob.
* generated output stays in `Lux.root`.

### Cleanup

* remove `lib/lux/plugin/mount.rb`, `bin/cli/mount_hammer.rb`, the
  `.git/info/exclude` writer and the `pack_hammer` mount path.
* delete the app mount symlinks and the `rollup.config.js` symlink.

## Milestones

1. `Lux::Root` plus the resolution API, plugin `mount/` auto-registered;
   symlinks still present and ignored.
2. require, autoload and templates migrated.
3. assets and the rollup generated-config exception.
4. symlink machinery, app links and exclude block removed.
5. docs and specs.

## Risks

* shadowing must be identical across require, templates and assets.
* `DEPLOY_ID` and backtrace decoration only strip `Lux.root`; gem roots need
  handling too.
* the reloader skips `Gem.path`; plugin files must still reload in dev.
* sass `@import` and the `@lib` alias need validation from gem paths.
* no per-file plugin disable; only app-root shadowing.
