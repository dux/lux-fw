# Lux Framework

Ruby web framework - Rack-based, Sequel ORM, PostgreSQL.

## Project structure

* `lib/lux/` - core modules (application, cache, config, controller, current, db, environment, error, logger, mailer, plugin, render, response, template)
* `lib/overload/` - Ruby core class extensions (18 files)
* `lib/common/` - shared utilities (Crypt, StringBase, StructOpts, TimeDifference)
* `plugins/` - framework plugins loaded via `Lux.plugin :name`
  - `plugins/db/` - database (Sequel model extensions, auto-migrate, rake tasks)
  - `plugins/assets/` - CDN asset pipeline (cdn_asset, assets.rake, lux_helper)
  - `plugins/html/` - HTML builders (html_input, html_table, html_menu, html_filter, page_meta, time_zones)
  - `plugins/job_runner/` - background job queue (LuxJob - database-backed with cron scheduling)
  - `plugins/lux_logger/` - structured database logger (LuxLogger model)
  - `plugins/oauth/` - OAuth integration
  - `plugins/auto_controller/` - auto controller routing
* `spec/` - RSpec tests (`spec/lib_tests/`, `spec/lux_tests/`)
* `bin/` - CLI (`lux` command, `bin/cli/` has 15+ subcommands)
* `tasks/` - Rake tasks

## Key patterns

* Config loaded from `config/config.yaml` via `Lux.config` (HashWithIndifferentAccess)
* Database connections managed by `Lux::Db` (`lib/lux/db/db.rb`)
  - Config key is `db:` (not `dbs:`) - accepts string (single main DB) or hash (named DBs)
  - `Lux.db(:name)` returns Sequel::Database, `DB` constant is a lazy proxy
  - ENV override: `DB_MAIN`, `DB_LOG`, etc. `DB_URL` as fallback for `:main`, then `Lux.config[:db_url]`
  - `Lux::Db.configured_names` - list of configured DB names
  - `Lux::Db.disconnect_all` - disconnect and clear all connections
* Models use `ref` (string) as primary key, not integer `id`
* Sequel plugins registered under `plugins/db/` (hooks, links, parent_model, enums, etc.)
* `Lux.plugin :db` triggers `loader.rb` which calls `Lux::Db.boot!` then loads all plugin files

## Conventions

* Use `FOO ||=` for constants, not `FOO =`
* End all files with newline, no trailing spaces on empty lines
* Prefer `Lux::Db.connections` over `Lux.config.sequel_dbs` (legacy)

## Core components

### Lux module (`lib/lux/lux.rb`)

* `Lux.root` - Application root path (Pathname)
* `Lux.fw_root` - Framework root path (Pathname)
* `Lux.call(env)` - Main Rack entry point
* `Lux.speed { }` - Block execution timing (returns formatted string like "123.5 ms" or "1.23 sec")
* `Lux.delay(ttl) { }` - Execute block in background thread, optional time_to_live in seconds
* `Lux.log(msg)` - Logging helper (via logger adapter)
* `Lux.logger(:name)` - Named logger instance
* `Lux.info(msg)` - Console info in magenta
* `Lux.run(cmd)` - Run shell command with logging
* `Lux.die(msg)` - Stop execution and log error
* `Lux.app_caller` - Returns the application caller line (for logging context)

### Lux::Application (`lib/lux/application/`)

Router and request lifecycle:
* Class callbacks: `config`, `boot`, `info`, `before`, `routes`, `after`, `rescue_from`
* Routing methods: `root`, `map`, `call`, `match`
* `mount app_class => '/path'` - Mount Rack applications
* `favicon(path)` - Serve favicon.ico and apple-touch-icon files
* Request method helpers: `get?`, `post?`, `delete?`, `put?`, `patch?`, `head?` (also accept blocks)
* Nav object (`current.nav`) for URL parsing and manipulation

### Lux::Application::Nav (`lib/lux/application/lib/nav.rb`)

URL navigation helper accessible via `current.nav`:
* `nav.root` / `nav.root=` - First path segment
* `nav.child` - Second path segment
* `nav.path` / `nav.path=` - Path array or pattern matching (also accepts block)
* `nav.id` / `nav.id=` - Last matched ID
* `nav.ids` - Array of all parsed IDs
* `nav[index]` - Access original path segment by index
* `nav.format` - Request format (html, json, etc.)
* `nav.domain` / `nav.subdomain` - Domain parts
* `nav.base` - Base URL (scheme + host + port)
* `nav.shift` / `nav.unshift` - Path manipulation
* `nav.last` - Last path segment
* `nav.locale` / `nav.locale=` - Locale from path
* `nav.url(*args)` - URL object
* `nav.remove_www` - Redirect www to non-www
* `nav.rename_domain(from, to)` - Domain redirect
* `nav.pathname(ends:, has:)` - Path testing

### Lux::Controller (`lib/lux/controller/controller.rb`)

Request controllers with Rails-like interface:
* Callbacks: `before`, `before_action`, `before_render`, `after`
* Class attributes: `layout`, `template_root`
* `mock :show, :edit` - Create empty actions for template-only rendering (accepts multiple)
* `action_missing` - Called when action not found; default looks for matching template (requires `Lux.config.use_autoroutes`)
* Instance methods:
  - `render`, `redirect_to`, `send_file`, `flash`, `action`, `helper`, `respond_to`
  - `render_to_string(name, opts)` - Render template without setting response body
  - `timeout(seconds)` - Set custom app timeout for this action
  - `namespace` - Get controller namespace as symbol
  - `controller_action_call(controller_action, *args)` - Call another controller action

### Lux::Current (`lib/lux/current/`)

Thread-local request context accessible via `Lux.current` or `current`:
* `current.request` - Rack request
* `current.response` - Lux response
* `current.session` - JWT-encrypted session
* `current.nav` - URL navigation helper
* `current.params` - Request parameters
* `current.cookies` - Rack cookies
* `current.locale` - Current locale
* `current.var` - Request-scoped variables (CleanHash)
* `current[:key]` / `current[:key]=` - Shortcut for `current.var`
* `current.cache(key) { }` - Request-scoped caching
* `current.once { }` / `current.once(id) { }` - Execute only once per request
* `current.uid` - Unique ID per response
* `current.secure_token` - Session secure token
* `current.bearer_token` - Extract Bearer token from Authorization header
* `current.no_cache?` - Check if cache should be bypassed
* `current.can_clear_cache` - Allow cache clearing with SHIFT+refresh
* `current.ip` - Client IP address
* `current.host` - Current host
* `current.robot?` - Bot detection
* `current.mobile?` - Mobile device detection
* `current.encrypt(data)` / `current.decrypt(token)` - Request-scoped encryption
* `current.delay { }` - Background thread execution
* `current.files_in_use` - Track loaded files

### Lux::Response (`lib/lux/response/response.rb`)

HTTP response handling:
* `response.body` / `response.body=` - Get/set response body (setting halts processing)
* `response.body?` - Check if body is present
* `response.status` / `response.status=` - HTTP status code
* `response.header(key, value)` - Set response headers (no args returns headers hash)
* `response.content_type` / `response.content_type=` - Get/set content type
* `response.redirect_to(path)` - Redirect with flash support
* `response.permanent_redirect_to(path)` - 301 redirect
* `response.send_file(path, opts)` - File downloads (supports `inline:`, `file_name:`)
* `response.flash` - Flash messages (`flash.info`, `flash.error`, `flash.warning`)
* `response.etag(*args)` - ETag header with conditional response
* `response.max_age=` - Cache-Control max-age in seconds
* `response.public=` / `response.public?` - Set/check Cache-Control public
* `response.cached?` - Check if response has max_age > 0
* `response.halt(status, body)` - Halt and deliver response immediately
* `response.early_hints(link, type)` - HTTP early hints
* `response.auth(realm:, message:) { |user, pass| }` - Basic HTTP authentication
* `response.rack(klass, mount_at:)` - Mount Rack app

### Lux::Cache (`lib/lux/cache/cache.rb`)

* `Lux.cache.server` - Default memory backend
* `Lux.cache.server = :memcached` - Memcached backend
* `Lux.cache.fetch(key, ttl:) { }` - Fetch or compute
* `Lux.cache.fetch_if_true(key, opts) { }` - Like fetch but only caches truthy results
* `Lux.cache.read(key)` / `Lux.cache.get(key)` - Read cache
* `Lux.cache.write(key, data, ttl)` / `Lux.cache.set(key, data, ttl)` - Write cache
* `Lux.cache.delete(key)` - Delete cache entry
* `Lux.cache.read_multi(*keys)` / `Lux.cache.get_multi(*keys)` - Multi-read
* `Lux.cache[key]` / `Lux.cache[key]=` - Direct get/set without key generation
* `Lux.cache.lock(key, time) { }` - Distributed lock for block execution
* `Lux.cache.generate_key(*args)` - Key generation from objects (uses `:id`, `:updated_at`)
* `Lux.cache.is_available?` - Check if cache server is available

### Lux::Template (`lib/lux/template/`)

* `Lux::Template.render(scope, template:, layout:, &block)` - Block for layout content
* `Lux::Template.helper(scope, :name)` - Create helper with module methods
* Supports HAML, ERB, and other Tilt formats
* Template caching enabled in production

### Lux::Mailer (`lib/lux/mailer/mailer.rb`)

* `Mailer.deliver(:template, *args)` - Render and deliver
* `Mailer.render(:template, *args)` - Get body only
* `Mailer.prepare(:template, *args).deliver` - Prepare then deliver
* `Mailer.template_name(*args).deliver` - Rails-style via method_missing
* Callbacks: `before`, `after`
* Template rendering in `./app/views/mailer/`
* Layout in `./app/views/mailer/layout.haml`

### Lux::Error (`lib/lux/error/error.rb`)

Error methods generated from CODE_LIST (common ones):
* `Lux.error.bad_request(msg)` - 400
* `Lux.error.unauthorized(msg)` - 401
* `Lux.error.payment_required(msg)` - 402
* `Lux.error.forbidden(msg)` - 403
* `Lux.error.not_found(msg)` - 404
* `Lux.error.method_not_allowed(msg)` - 405
* `Lux.error.not_acceptable(msg)` - 406
* `Lux.error.internal_server_error(msg)` - 500
* `Lux.error.not_implemented(msg)` - 501
* `Lux::Error.render(error)` - Error page rendering
* `Lux::Error.inline(object, msg)` - Inline error display
* `Lux::Error.format(error, opts)` - Format backtrace (supports `html:`, `message:`, `gems:`)

### Lux::Environment (`lib/lux/environment/environment.rb`)

Environment detection via `Lux.env`. Three valid environments: `development`, `production`, `test` (set via `RACK_ENV` or `LUX_ENV`):
* `Lux.env.development?` / `Lux.env.dev?` - True when NOT production (includes test)
* `Lux.env.production?` / `Lux.env.prod?` - True only in production
* `Lux.env.test?` - True in test or when run via rspec
* `Lux.env.web?` - True when running under Rack/Puma server
* `Lux.env.cli?` - True when NOT running as web server
* `Lux.env.rake?` - True when run via rake
* `Lux.env.live?` - True when `ENV['LUX_LIVE'] == 'true'`
* `Lux.env.local?` - Inverse of `live?`
* `Lux.env.reload?` - True when `LUX_ENV` includes `r` flag
* `Lux.env.log?` - True when `LUX_ENV` includes `l` flag
* `Lux.env == :dev` - Comparison operator

### Lux::Config (`lib/lux/config/config.rb`)

`Lux.config` returns a hash (with indifferent access) loaded from `config/config.yaml`:
* `Lux.config.key = value` / `Lux.config.key`
* `Lux.config.all` - Get all config
* `Lux::Config.app_timeout` - Get current app timeout
* `Lux::Config.ram` - Current process RAM usage in MB
* `Lux::Config.start_info` - Formatted boot time info
* Hooks: `on_reload_code { }`, `on_mail_send { |mail| }`

### Lux::Plugin (`lib/lux/plugin/plugin.rb`)

* `Lux.plugin(name_or_folder)` - Load a plugin
* `Lux.plugin(name:, folder:, namespace:)` - Load with options
* `Lux.plugin.get(:name)` - Get loaded plugin
* `Lux.plugin.loaded` - All loaded plugin values
* `Lux.plugin.keys` - Loaded plugin names
* `Lux.plugin.folders(namespace)` - Plugin folders by namespace

### Lux::Application::Render (`lib/lux/render/`)

* `Lux.render(path, opts)` - Render full page
* `Lux.render.get(path, params, opts)` - GET request render
* `Lux.render.post(path, params, opts)` - POST request render
* `Lux.render.delete(...)` / `.patch(...)` / `.put(...)` - Other methods
* `Lux.render.controller('main#index')` - Render controller action directly (accepts block for setup)
* `Lux.render.template(scope, template)` - Render template
* `Lux.render.cell(name, context, opts)` - Render ViewCell

## Ruby core extensions (`lib/overload/`)

### Object (`object.rb`, `blank.rb`, `boolean.rb`, `raise_variants.rb`)
* `obj.or(default)` - Return default if blank or zero
* `obj.try(:method)` - Safe method call (nil on NilClass)
* `obj.presence` - Return self if present, nil otherwise
* `obj.present?` / `obj.blank?` - Presence checks
* `obj.is!(Type)` - Type assertion (raises on mismatch), without arg checks presence
* `obj.is?(Type)` - Boolean type check
* `obj.is_hash?`, `obj.is_array?`, `obj.is_string?`, `obj.is_numeric?`, `obj.is_symbol?`, `obj.is_boolean?`
* `obj.is_true?` / `obj.is_false?` - Truthy string check (`'true'`, `'on'`, `'1'`)
* `obj.to_b` - Convert to boolean
* `obj.andand(func)` - Safe chain (present? check)
* `obj.die(msg)` - Print error and raise
* `r(what)` - Raise with inspect/JSON (global)
* `rr(what)` - Console log dump with context (global)
* `LOG(what)` - Write to `./log/LOG.log` (global)

### String (`string.rb`)
* `str.constantize` / `str.constantize?` - Convert to constant
* `str.parameterize` / `str.to_url` - URL-safe string (max 50 chars)
* `str.to_slug(len)` - Slug format with hyphens
* `str.trim(len)` - Truncate with ellipsis
* `str.squish` - Collapse whitespace
* `str.html_escape` / `str.html_safe` / `str.html_unsafe` - HTML encoding
* `str.as_html` - Simple markdown (newlines to `<br>`, URLs to links)
* `str.sanitize` / `str.quick_sanitize` - HTML sanitization
* `str.sha1` / `str.md5` - Hash digests
* `str.wrap(:tag, opts)` - Wrap in HTML tag
* `str.escape` / `str.unescape` - URL encoding
* `str.colorize(:color)` / `str.decolorize` - ANSI terminal colors
* `str.first` / `str.last(n)` - Character access
* `str.qs_to_hash` - Parse query string to hash

### Hash (`hash.rb`)
* `hash.to_query` - Convert to URL query string
* `hash.to_attributes` - Convert to HTML attributes
* `hash.to_css` - Convert to CSS inline style
* `hash.deep_sort` - Recursively sort keys
* `hash.pluck(*keys)` - Select specific keys
* `hash.remove_empty` - Remove blank entries
* `hash.deep_compact` - Recursively remove empty values
* `hash.to_js(opts)` - JSON without quoted keys

### Array (`array.rb`)
* `array.to_csv` - Convert to CSV (semicolon-delimited)
* `array.to_sentence(opts)` - Rails-like sentence join
* `array.toggle(el)` - Toggle element presence
* `array.to_ul(class)` - Convert to HTML list
* `array.wrap(tag, opts)` - Wrap each element in HTML tag
* `array.xuniq` - Unique non-blank elements
* `array.xmap` - Map with 1-based counter

### Integer (`integer.rb`)
* `int.pluralize(:noun)` - Smart pluralization (`0.pluralize(:cat)` -> `"no cats"`)
* `int.dotted` - Dot-separated thousands (`1234567` -> `"1.234.567"`)
* `int.to_filesize` - Human-readable file size
* `int.string_id` - Encode to StringBase short string

### Float (`float.rb`)
* `float.as_currency(opts)` - Currency formatting (European style)
* `float.dotted(round)` - Dot-thousands, comma-decimal

### Dir (`dir.rb`)
* `Dir.folders(dir)` - List subdirectories
* `Dir.files(dir, opts)` - List files
* `Dir.find(dir, opts)` - Deep file search with filtering
* `Dir.require_all(folder)` - Require all `.rb` files recursively
* `Dir.mkdir?(name)` - Create directory path

### Other extensions
* `Class#descendants` - All descendant classes (`class.rb`)
* `Class#source_location` - Source file path (`class.rb`)
* `File.write_p`, `File.append`, `File.ext`, `File.delete?`, `File.is_locked?` (`file.rb`)
* `Pathname#touch`, `Pathname#write_p`, `Pathname#folders`, `Pathname#files` (`pathname.rb`)
* `Struct#to_hash` (`struct.rb`)
* `NilClass#empty?`, `NilClass#is?` (`nil.rb`)
* `Boolean.parse`, `TrueClass#to_i`, `FalseClass#to_i` (`boolean.rb`)
* `Thread::Simple` - Thread pool (`thread_simple.rb`)
* `Hash#to_jsons`, `Hash#to_jsonp`, `Hash#to_jsonc` (`json.rb`)
* `Time#short`, `Time#long`, `Time.speed`, `Time.ago` (`time.rb`)

## Common utilities (`lib/common/`)

### Crypt (`lib/common/crypt.rb`)
* `Crypt.encrypt(data, ttl:, password:)` - JWT encryption (HS512)
* `Crypt.decrypt(token, password:, unsafe:)` - JWT decryption
* `Crypt.short_encrypt(data, ttl)` / `Crypt.short_decrypt(data)` - Lightweight Base64 encoding
* `Crypt.simple_encode(str)` / `Crypt.simple_decode(str)` - Base64 + ROT13 (JS interop)
* `Crypt.sha1(str)` / `Crypt.md5(str)` - Salted hash digests
* `Crypt.uid(size)` - Random alphanumeric (default 32 chars)
* `Crypt.random(length)` - Random string (no ambiguous chars)
* `Crypt.bcrypt(plain, check)` - BCrypt password hashing
* `Crypt.base64(str)` - URL-safe Base64
* `Crypt.secret` - Secret from ENV or config

### StringBase (`lib/common/string_base.rb`)
* `StringBase.encode(int)` / `StringBase.decode(str)` - Obfuscated ID encoding
* `StringBase.short` / `StringBase.medium` / `StringBase.long` - Different key sets
* `StringBase.uid` - Time-based unique ID

### StructOpts (`lib/common/struct_opts.rb`)
* `StructOpts(vars, opts)` - Create Struct from hash with defaults

### TimeDifference (`lib/common/time_difference.rb`)
* `TimeDifference.new(start, end).humanize` - Human-readable time difference

## Routing patterns

```ruby
Lux.app do
  before { }

  routes do
    root 'main#index'
    map about: 'main#about' if get?

    map 'admin' do
      root 'admin/dashboard#index'
      map users: 'admin/users'
    end

    map '/users/:id' => 'users#show'

    mount ApiApp => '/api'
  end

  after { }
  rescue_from { |e| }
end
```

## Controller patterns

```ruby
class UsersController < ApplicationController
  layout :application
  before { @user = User.current }
  mock :show, :edit

  def index
    @users = User.all
    # Renders ./app/views/users/index.haml
  end
end
```

Render options: `text:`, `plain:`, `html:`, `json:`, `javascript:`, `template:`

## Model associations (`link`)

```ruby
class Task < ApplicationModel
  schema do
    link :board       # DB: board_ref column + index + foreign key
  end

  link :board         # Ruby: task.board -> Board.find(board_ref)
  link :comments      # Ruby: task.comments -> Comment.where(task_ref: ref)
end
```

* `link :user` - singular, belongs_to via `user_ref` column
* `link :users` - plural, has_many via reverse lookup
* `link :user, class: 'OrgUser'` - custom class
* `link :user, field: 'owner_ref'` - custom field

## Dirty tracking (`on_change`)

```ruby
user.on_change(:name) { |prev, cur| ... }
```

## Rake DB tasks

* `rake db:info` - show configured databases and existence status
* `rake db:create` - create databases if missing
* `rake db:drop` - drop all databases (main + test)
* `rake db:reset` - drop, create, auto migrate
* `rake db:am` - auto migrate schema (`db:am[y]` to auto-confirm drops)
* `rake db:seed` - reset + load seed data from `./db/seeds/`
* `rake db:backup` / `rake db:restore` - SQL dump/restore to `./tmp/db_dump/`
* `rake db:console` - open psql console (`db:console[name]` for named DB)
* `rake db:create:test` - recreate test DBs (drop if exists, copy schema from main)
* `rake db:drop:test` - drop test databases only
* `rake db:gen_seeds[model,ref]` - generate seed code from model records

Destructive tasks are blocked in production. Test databases use `_test` suffix.

## CLI commands

```bash
lux server       # Start web server (aliases: s, ss, silent)
lux console      # Start Pry console (alias: c)
lux evaluate     # Eval ruby string in Lux context (alias: e)
lux get /path    # Fetch single page by path
lux generate     # Generate models, cells, controllers
lux test         # Recreate test DB + run full test suite (alias: t)
lux config       # Show configuration
lux secrets      # Display/edit ENV and secrets
lux stats        # Print project statistics
lux benchmark    # Benchmark app boot time
lux memory       # Profile memory usage
lux plugin       # Show loaded plugins
lux new APP      # Create new Lux application
lux cerb         # Parse .cerb (CLI ERB) templates
lux template     # Parse file with ENV variable substitution
lux sysd         # Systemd service management
```

## Testing

* `bundle exec rspec` from project root
* Tests in `spec/lib_tests/` (pure ruby) and `spec/lux_tests/` (framework features)
* `lux test` (or `lux t`) - recreate test DB + run full test suite
* `lux test spec/path` - run specific test file (no DB recreation)

## Dependencies

Key gems: `rack`, `sequel_pg`, `haml`, `jwt`, `mail`, `hash_wia`, `class-callbacks`, `class-cattr`, `view-cell`, `as-duration`, `typero`, `thor`, `pry`, `dotenv`, `deep_merge`, `amazing_print`, `niceql`, `whirly`, `tty-prompt`

## Configuration files

* `./config/environment.rb` - Main boot file
* `./config/application.rb` - Application setup
* `./config/config.yaml` - YAML configuration (default + per-environment)
* `./app/routes.rb` - Route definitions
