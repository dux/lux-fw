# Hammer migration

Replace Thor + Rake in lux-fw (and lux apps) with `lux-hammer`. Unified
`lux <cmd>` experience.

## Goal

* Single `bin/lux` entrypoint dispatches via `lux-hammer`.
* lux core commands live in **root namespace** (e.g. `lux server`).
* Plugins each ship a `*_hammer.rb` fragment in their own namespace
  (e.g. `lux db:am`, `lux job_runner:start`).
* Apps drop a `Hammerfile` with `load auto: true` to pull in everything.
* No Thor, no Rake.

## Plan

### Phase A - lux-hammer 0.2.0

Done in `~/dev/dux/gems/hammer`.

1. **Add `before(&blk)`** to `Hammer::Builder` only (root + namespace
   scope; not `CommandBuilder`). Stored on each `Hammer::Namespace`
   and the root class. Dispatcher runs ancestor `before` hooks in
   outer -> inner order before the command's `handler.call`.
2. **Add `needs :path, ...`** inside `define` (CommandBuilder scope) -
   declares prereq commands run before the handler. Rake-style
   `task :x => :env` equivalent. Dedupes per top-level `start`
   invocation. Added by the user after the initial pass; replaces
   the `before { hammer_env }` pattern for most lux plugins.
3. **Hide empty-`desc` commands** from help listings (root +
   namespace). Commands stay dispatchable + `hammer_*`-callable.
4. Tests: nested namespace before-hook inheritance + order, hidden
   commands absent from listings but resolvable, `needs` dedupe + chain.
5. README note, bump `.version` to 0.2.0, build + publish.

### Phase B - lux-fw migration

Done here.

1. **`Hammerfile` at lux-fw root** with `load auto: true` and hidden
   helpers:
   ```ruby
   define :env do; proc { require './config/env' }; end
   define :app do; proc { require './config/app' }; end
   ```
2. Port every `bin/cli/*.rb` Thor file to `bin/cli/*_hammer.rb` in
   **root namespace**.
3. Port every `*.rake` to `*_hammer.rb` next to the plugin, wrapped in
   `namespace :<plugin> do ... end`. Per-command `needs :env` /
   `needs :app` declarations match the original rake `=> :env` /
   `=> :app` 1:1. Plugins whose rake tasks had no prereq (assets,
   exceptions, nginx) declare no `needs`.
4. Rewrite `bin/lux` to ~30 lines: env setup, version banner,
   `Hammer.start ARGV`. Pry/AmazingPrint moves into `console_hammer.rb`.
5. Delete `tasks/loader.rb`, `Lux.load_tasks`, all `*.rake`,
   `misc/demo/Rakefile`, the rake-T/cap-T/mina-T fallback in `bin/lux`.
6. Drop `thor` + `whirly` from gemspec/Gemfile (verify whirly unused).
7. `alt :s` on `:server`. `lux ss` dropped.
8. Bump lux-fw `.version`, run `bin/lux test`, verify `lux`, `lux -h`,
   `lux db`, `lux db:am`, `lux server -h` all work.

## Files

### Created
* `Hammerfile`
* `bin/cli/*_hammer.rb` (16 files, one per current Thor file)
* `plugins/db/auto_migrate/db_hammer.rb`
* `plugins/job_runner/job_runner_hammer.rb`
* `plugins/assets/assets_hammer.rb`
* `plugins/arhive/log_exception/exceptions_hammer.rb`
* `plugins/arhive/nginx/nginx_hammer.rb`
* `tasks/sysd_hammer.rb`

### Modified
* `bin/lux`
* `lib/lux/config/lux_adapter.rb` (remove `Lux.load_tasks`)
* `lux-fw.gemspec` / `Gemfile` (drop thor/whirly)

### Deleted
* `tasks/loader.rb`
* `tasks/sysd.rake`
* `plugins/assets/assets.rake`
* `plugins/job_runner/tasks/job_runner.rake`
* `plugins/db/auto_migrate/db.rake`
* `plugins/arhive/log_exception/exceptions.rake`
* `plugins/arhive/nginx/nginx.rake`
* `misc/demo/Rakefile` (or replaced with one-line `Hammerfile`)
* All `bin/cli/*.rb` Thor files

## Mapping cheat sheet

| Thor / Rake                                                  | Hammer                                                                   |
|--------------------------------------------------------------|--------------------------------------------------------------------------|
| `desc :x, '...'; method_option :p; def x; options[:p]; end`  | `define :x do; desc '...'; opt :p; proc { \|o\| o[:p] }; end`            |
| `task :x => :env do ... end`                                 | `define :x do; needs :env; proc {...}` (or namespace-level `before { hammer_env }`) |
| `namespace :db do; task :am do ... end; end`                 | `namespace :db do; define :am do; proc do ... end; end; end`             |
| `Rake::Task['db:am'].invoke`                                 | `hammer_db_am`                                                           |
| `Cli.run cmd` / `system cmd` w/ echo                         | `sh cmd`                                                                 |
| `Cli.die msg`                                                | `error msg`                                                              |
| `puts text.colorize(:red)`                                   | `say.red text`                                                           |
| `args[:name]` positional                                     | `opts[:args].first` or declared `opt :name` (positional fill)            |
