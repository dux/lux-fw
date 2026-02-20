# Lux Framework - TODO

## Router: Replace with Roda

The custom router (`lib/lux/application/lib/routes.rb`) has accumulated complexity.
Roda is a natural fit - same routing-tree concept, Rack-native, maintained by Jeremy Evans (Sequel author).

- [ ] `map` method has 6+ calling conventions (String, Hash, Array, Symbol+block, Hash+block, etc.)
- [ ] `map.about` dot syntax appears broken - no `method_missing` to support it, but demo uses it
- [ ] `test?` has side effects - both tests AND mutates path via `nav.shift`
- [ ] README says `map :city do` calls a `city_map` method, but code just does string comparison
- [ ] `call` method is 75 lines handling every type (Symbol, Hash, String, Array, Proc, Class, Module)
- [ ] Adopt Roda-style: route blocks ARE the actions, controllers become optional organizational units
- [ ] Roda `multi_route` plugin can give controller-like route file organization

## Nav: Refactor in Place

Strip the mutable cursor role (let Roda handle that), keep useful URL parsing.

- [ ] Remove mutable cursor methods (`shift`, `unshift`) once Roda handles routing
- [ ] Rename `nav.root` - it means "first unconsumed segment" which conflicts with `root` in route DSL
- [ ] Rename `nav.querystring` - it contains colon-param values (`/key:val`), not the actual query string
- [ ] Replace `nav.base` with `Rack::Request#base_url` (current impl does fragile string split)
- [ ] Stop reaching into `Lux.current.response` from Nav (`remove_www`, `rename_domain` do redirects)
- [ ] Remove `path_id` dead method (just raises "use av.path {...}")
- [ ] Remove commented-out block form in `last` method
- [ ] Remove "experiment for different nav in rooter" comment on line 1
- [ ] `set_domain` uses magic number (`length == 5`) for `.co.uk` detection - misses `.com.au`, `.org.uk`

## Route/Controller Deduplication

Both layers include `Lux::Application::Shared`, creating overlap.

- [ ] `get?`/`post?` exist in both layers with different capabilities (controller only has 2, routes has 6 + block forms)
- [ ] `before`/`after` callbacks exist in both layers - two separate chains run per request
- [ ] `rescue_from` exists in both with different mechanisms
- [ ] `render` exists in both with completely different semantics
- [ ] Instance variables are implicitly copied from router to controller via `ivars: instance_variables_hash`
- [ ] Once Roda is adopted, remove duplicated features from the route layer

## Monkey Patches: Clean Up (`lib/overload/`)

Highest risk area in the codebase. Many shadow Ruby stdlib or conflict with gems.

### Remove (already in Ruby stdlib)
- [ ] `Hash#slice` - built-in since Ruby 2.5
- [ ] `Hash#except` - built-in since Ruby 3.0
- [ ] `Hash#transform_keys` - built-in since Ruby 2.5
- [ ] `Hash#symbolize_keys` / `Hash#stringify_keys` - trivial via `transform_keys`
- [ ] `NilClass#dup` - built-in since Ruby 2.4
- [ ] `String#starts_with?` - Ruby has `start_with?`

### Fix or Gate
- [ ] `Object.const_missing` hijacks Ruby autoload globally, shells out to `find` to scan `./app`
- [ ] `Object#or`, `Object#and`, `Object#nil`, `Object#try` - collision risk with ActiveSupport/refinements
- [ ] `Object#blank?`, `Object#present?` - collision risk with ActiveSupport
- [ ] `Object#empty?` aliased to `blank?` is semantically wrong (`0.empty?` should not exist)
- [ ] `String#to_a` splits on comma - overrides removed stdlib method with surprising behavior
- [ ] `Dir.find` uses fragile shell `echo` + glob, breaks on filenames with spaces
- [ ] `Dir.require_all` depends on fragile `Dir.find`
- [ ] `Hash#blank?` defined twice (in `blank.rb` and `hash.rb`)

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
- [ ] `colorize` - terminal colors, should be optional
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

- [ ] `application.rb:55` `rescue_from` catches all exceptions including `SystemExit`, `Interrupt` - should be `rescue StandardError`
- [ ] `environment.rb` `development?` returns `@env_name != 'production'` - test env is considered dev
- [ ] `controller.rb` `@lux.template_suffix` only takes first namespace segment - `Main::RootController` resolves to `main/` not `main/root/`
- [ ] `controller.rb` `@controller_action` attr_reader declared but never assigned - dead code
- [ ] `response.rb:273` content-type detection `@body[0,1] != '<'` is fragile
- [ ] `response.rb:185` `<script>location.href=...</script>` redirect - XSS in `<p>` tag for `opts.values` still unescaped
- [ ] `template.rb:3` `@@template_cache = {}` class variable is never used
- [ ] `template.rb:49` layout paths cached in memcached/memory server - overkill for file paths
- [ ] `helper.rb` `render` method is extremely overloaded - accepts strings, symbols, arrays, objects with `db_schema`
- [ ] `inline_render_proxy.rb` has `method_missing` without `respond_to_missing?`
- [ ] `mailer.rb` has `method_missing` without `respond_to_missing?`
- [ ] `mailer.rb` `deliver` sends email in background thread via `Lux.current.delay` - no retry, no queue
- [ ] `mailer.rb` only supports `text/html` content type - no plaintext fallback or multipart
- [ ] `helper_modules.rb` defines global `ApplicationHelper` and `HtmlHelper` - very generic namespace names
- [ ] `Lux.var` returns process-global `Lux::CACHE` hash, while `Lux.current.var` is request-scoped - confusing
- [ ] `current/lib/current.rb` defines top-level `Current` class - pollutes global namespace, conflicts with Rails
- [ ] `current/lib/lux_adapter.rb` adds `Object#lux` method to every object

## Global Namespace Pollution

- [ ] Top-level `Current` class (not `Lux::Current`)
- [ ] `Object#lux` method on every object
- [ ] Global `Lux()` function defined on Object via `def Lux`
- [ ] `StructOpts()` global function
- [ ] `ApplicationHelper`, `HtmlHelper`, `MailerHelper` modules in root namespace
- [ ] `$rack_handler` global variable
- [ ] `$lux_start_time` global variable
