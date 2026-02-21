# Lux Framework - TODO

## Router: Replace with Roda

The custom router (`lib/lux/application/lib/routes.rb`) has accumulated complexity.
Roda is a natural fit - same routing-tree concept, Rack-native, maintained by Jeremy Evans (Sequel author).

- [ ] `map` method has 6+ calling conventions (String, Hash, Array, Symbol+block, Hash+block, etc.)
- [ ] `call` method is 75 lines handling every type (Symbol, Hash, String, Array, Proc, Class, Module)

## Nav: Refactor in Place

Strip the mutable cursor role (let Roda handle that), keep useful URL parsing.

- [ ] Remove mutable cursor methods (`shift`, `unshift`) once Roda handles routing
- [ ] Rename `nav.root` - it means "first unconsumed segment" which conflicts with `root` in route DSL
- [ ] Replace `nav.base` with `Rack::Request#base_url` (current impl does fragile string split)
- [ ] Stop reaching into `Lux.current.response` from Nav (`remove_www`, `rename_domain` do redirects)

## Route/Controller Deduplication

Both layers include `Lux::Application::Shared`, creating overlap.

- [x] `get?`/`post?` removed from controller (use `request.get?`, `request.post?` etc. from Rack instead)
- [ ] `before`/`after` callbacks exist in both layers - two separate chains run per request
- [x] `rescue_from` unified — removed from Controller, single handler in Application with Lux-branded default
- [x] `render` in Application now matches controller interface (template via controller, static content, full page render via `render_page`)
- [ ] Instance variables are implicitly copied from router to controller via `ivars: instance_variables_hash`

## Monkey Patches: Clean Up (`lib/overload/`)

Highest risk area in the codebase. Many shadow Ruby stdlib or conflict with gems.

### Remove (debug/dev only)
- [ ] `Object#r`, `Object#rr`, `Object#LOG`, `Object#r?`, `Object#m?` - debug methods on every object
- [ ] `Object#LOG` creates a new Logger instance on every call

## Security

- [ ] `Crypt.simple_encode`/`simple_decode` use ROT13 + Base64 - document as not-for-security
- [ ] `String#sanitize` calls `Sanitize.clean` but `sanitize` gem is not in gemspec - crashes at runtime
- [ ] `Lux.run` uses backtick interpolation (`#{command}`) - command injection risk pattern
- [ ] `loader.rb:41` uses backtick `` `mkdir #{d}` `` instead of `FileUtils.mkdir_p`
- [ ] `Lux.call` wraps in `Timeout::timeout` which is known-unsafe in Ruby (uses `Thread.raise`)
- [ ] Session data is entirely in JWT cookie - cannot be invalidated server-side, can grow large
- [ ] `session.rb:23` blanket `rescue {}` swallows all errors including programming bugs

## Thread Safety

- [ ] `MemoryServer#get` reads `@@ram_cache`/`@@ttl_cache` without mutex (only `set`/`delete` are locked)
- [ ] `MemoryServer.clear` assigns new hashes without mutex
- [ ] `Controller::HELPERS` is a process-global hash with no synchronization on write
- [ ] `action_missing` calls `self.class.define_method` - mutates class object across all threads
- [ ] `Lux::PLUGIN` constant is a mutable Hash with no thread safety
- [ ] `Lux.delay` spawns raw threads with no pool limit - unbounded under load

## Dependencies (gemspec)

### Move to optional/development
- [ ] `pry` - dev console, not needed at runtime
- [ ] `amazing_print` - pretty printing, dev only
- [ ] `niceql` - SQL formatting, dev only
- [ ] `sequel_pg` - framework should not mandate a specific ORM
- [ ] `haml` - Tilt supports many engines, should be optional
- [ ] `tty-prompt` - only used in CLI
- [ ] `whirly` - only used in CLI
- [ ] `typero` - used in one place (params validation)
- [ ] `mail` - only needed if using the mailer
- [ ] `thor` - only needed for CLI

### Missing
- [ ] `tilt` - core template dependency, not listed
- [ ] `sanitize` - called in `String#sanitize` but not in gemspec
- [ ] No version constraints on any dependency

### Other
- [ ] Gemspec uses backtick `find` to build file list - should use `Dir.glob` or `git ls-files`
- [ ] Typo in description: "linghtness" should be "lightness"

## Code Quality

- [ ] `environment.rb` `development?` returns `@env_name != 'production'` - test env is considered dev
- [ ] `controller.rb` `@lux.template_suffix` only takes first namespace segment - `Main::RootController` resolves to `main/` not `main/root/`
- [ ] `response.rb:273` content-type detection `@body[0,1] != '<'` is fragile
- [ ] `response.rb:185` `<script>location.href=...</script>` redirect - XSS in `<p>` tag for `opts.values` still unescaped
- [x] `template.rb:49` layout paths cached in memcached/memory server - now uses process-local hash (same pattern as `compile_template`)
- [x] `helper.rb` `render` simplified - accepts only strings/symbols (removed dead array and `db_schema` branches)
- [ ] `inline_render_proxy.rb` has `method_missing` without `respond_to_missing?`
- [ ] `mailer.rb` has `method_missing` without `respond_to_missing?`
- [ ] `mailer.rb` `deliver` sends email in background thread via `Lux.current.delay` - no retry, no queue
- [ ] `mailer.rb` only supports `text/html` content type - no plaintext fallback or multipart
- [ ] `helper_modules.rb` defines global `ApplicationHelper` and `HtmlHelper` - very generic namespace names
- [ ] `current/lib/lux_adapter.rb` adds `Object#lux` method to every object

## Global Namespace Pollution

- [ ] Top-level `Current` class (not `Lux::Current`)
- [ ] `Object#lux` method on every object
- [ ] Global `Lux()` function defined on Object via `def Lux`
- [ ] `StructOpts()` global function
- [ ] `ApplicationHelper`, `HtmlHelper`, `MailerHelper` modules in root namespace
- [ ] `$rack_handler` global variable
- [ ] `$lux_start_time` global variable
