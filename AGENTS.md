# Lux Framework - AI Agent Guidelines

This document provides comprehensive guidance for AI agents working with the Lux web framework codebase.

## Framework Overview

Lux is a lightweight, Rack-based Ruby web framework designed for speed and simplicity. It provides a Rails-like interface with Sinatra-like performance.

**Key characteristics:**
- Rack-based architecture
- Explicit over magic approach
- JWT-based encrypted sessions
- HAML/ERB template support via Tilt (transitive dep via haml)
- PostgreSQL ORM via Sequel

## Project Structure

```
lux-fw/
├── bin/
│   ├── cli/           # CLI commands (server, console, generate, etc.)
│   ├── lux            # Main CLI entry point (Thor-based)
│   └── lux-sysd       # Standalone systemd TUI manager
├── lib/
│   ├── lux/           # Core framework modules
│   │   ├── application/   # Router, request lifecycle, Nav
│   │   ├── cache/         # Caching (memory, memcached, null)
│   │   ├── config/        # Configuration management
│   │   ├── controller/    # Request controllers
│   │   ├── current/       # Request context (session, cookies, params)
│   │   ├── environment/   # Environment detection
│   │   ├── error/         # Error handling and HTTP status codes
│   │   ├── logger/        # Logging adapter (Lux.log, Lux.logger)
│   │   ├── mailer/        # Email sending via mail gem
│   │   ├── plugin/        # Plugin system
│   │   ├── render/        # Page/template rendering
│   │   ├── response/      # HTTP response, flash, file serving
│   │   └── template/      # Template engine via Tilt
│   ├── overload/      # Ruby core class extensions (18 files)
│   ├── common/        # Utilities (Crypt, StringBase, StructOpts, TimeDifference)
│   ├── lux-fw.rb      # Main entry point (requires bundler + loader)
│   └── loader.rb      # Framework loader
├── misc/              # Demo app, nginx config, benchmarks
│   └── demo/          # Demo application
├── plugins/           # Framework plugins
│   ├── assets/        # Asset compilation (JS, CSS, Svelte)
│   ├── auto_controller/
│   ├── db/            # Database tasks and auto-migration
│   ├── html/          # HTML helpers
│   ├── job_runner/    # Background job processing
│   ├── lux_logger/    # Logger plugin
│   ├── oauth/         # OAuth integration
│   └── arhive/        # Archived plugins (delay, log_exception, nginx)
├── spec/              # RSpec tests
├── tasks/             # Rake task loader
└── doc/               # Notes and TODOs
```

## Core Components

### Lux Module (`lib/lux/lux.rb`)
Main entry point providing:
- `Lux.root` - Application root path (Pathname)
- `Lux.fw_root` - Framework root path (Pathname)
- `Lux.call(env)` - Main Rack entry point
- `Lux.speed { }` - Block execution timing (returns ms)
- `Lux.delay { }` - Execute block in background thread
- `Lux.log(msg)` - Logging helper (via logger adapter)
- `Lux.logger(:name)` - Named logger instance
- `Lux.info(msg)` - Console info in magenta
- `Lux.run(cmd)` - Run shell command with logging
- `Lux.die(msg)` - Stop execution and log error

### Lux::Application (`lib/lux/application/`)
Router and request lifecycle:
- Class callbacks: `config`, `boot`, `info`, `before`, `routes`, `after`, `rescue_from`
- Routing methods: `root`, `map`, `call`, `match`
- Request method helpers: `get?`, `post?`, `delete?`, `put?`, `patch?`, `head?` (also accept blocks)
- Nav object (`current.nav`) for URL parsing and manipulation

### Lux::Application::Nav (`lib/lux/application/lib/nav.rb`)
URL navigation helper accessible via `current.nav`:
- `nav.root` / `nav.root=` - First path segment
- `nav.child` - Second path segment
- `nav.path` / `nav.path=` - Path array or pattern matching
- `nav.id` / `nav.id=` - Last matched ID
- `nav.format` - Request format (html, json, etc.)
- `nav.domain` / `nav.subdomain` - Domain parts
- `nav.base` - Base URL (scheme + host + port)
- `nav.shift` / `nav.unshift` - Path manipulation
- `nav.last` - Last path segment
- `nav.locale` / `nav.locale=` - Locale from path
- `nav.url(*args)` - URL object
- `nav.remove_www` - Redirect www to non-www
- `nav.rename_domain(from, to)` - Domain redirect
- `nav.pathname(ends:, has:)` - Path testing

### Lux::Controller (`lib/lux/controller/controller.rb`)
Request controllers with Rails-like interface:
- Callbacks: `before`, `before_action`, `before_render`, `after`
- Class attributes: `layout`, `template_root`
- Instance methods: `render`, `redirect_to`, `send_file`, `flash`, `action`, `helper`, `respond_to`
- `action_missing` - Called when action not found; default looks for matching template (requires `Lux.config.use_autoroutes`)
- `mock :action` - Create empty action for template-only rendering

### Lux::Current (`lib/lux/current/`)
Thread-local request context accessible via `Lux.current` or `current`:
- `current.request` - Rack request
- `current.response` - Lux response
- `current.session` - JWT-encrypted session
- `current.nav` - URL navigation helper
- `current.params` - Request parameters
- `current.cookies` - Rack cookies
- `current.locale` - Current locale
- `current.var` - Request-scoped variables (CleanHash)
- `current[:key]` - Shortcut for `current.var.key`
- `current.cache(key) { }` - Request-scoped caching
- `current.once { }` / `current.once(key, data)` - Execute only once per request
- `current.uid` - Unique ID per response
- `current.secure_token` - Session secure token
- `current.no_cache?` - Check if cache should be bypassed
- `current.can_clear_cache` - Allow cache clearing with SHIFT+refresh
- `current.ip` - Client IP address
- `current.host` - Current host
- `current.robot?` - Bot detection
- `current.mobile?` - Mobile device detection
- `current.encrypt(data)` / `current.decrypt(token)` - Request-scoped encryption
- `current.delay { }` - Background thread execution
- `current.files_in_use` - Track loaded files

### Lux::Response (`lib/lux/response/response.rb`)
HTTP response handling:
- `response.body` / `response.body=` - Get/set response body (setting halts processing)
- `response.body?` - Check if body is present
- `response.status` / `response.status=` - HTTP status code
- `response.header(key, value)` - Set response headers
- `response.content_type` / `response.content_type=` - Get/set content type
- `response.redirect_to(path)` - Redirect with flash support
- `response.permanent_redirect_to(path)` - 301 redirect
- `response.send_file(path, opts)` - File downloads (supports `inline:`, `file_name:`)
- `response.flash` - Flash messages (`flash.info`, `flash.error`, `flash.warning`)
- `response.etag(*args)` - ETag header with conditional response
- `response.max_age=` - Cache-Control max-age in seconds
- `response.public=` - Set Cache-Control to public
- `response.halt(status, body)` - Halt and deliver response immediately
- `response.early_hints(link, type)` - HTTP early hints
- `response.auth { |user, pass| }` - Basic HTTP authentication

### Lux::Cache (`lib/lux/cache/cache.rb`)
Caching with multiple backends:
- `Lux.cache.server` - Default memory backend
- `Lux.cache.server = :memcached` - Memcached backend
- `Lux.cache.fetch(key, ttl:) { }` - Fetch or compute
- `Lux.cache.read(key)` / `Lux.cache.get(key)` - Read cache
- `Lux.cache.write(key, data, ttl)` / `Lux.cache.set(key, data, ttl)` - Write cache
- `Lux.cache.delete(key)` - Delete cache entry
- `Lux.cache.read_multi(*keys)` / `Lux.cache.get_multi(*keys)` - Multi-read
- `Lux.cache.generate_key(*args)` - Key generation from objects (uses `:id`, `:updated_at`)
- `Lux.cache.is_available?` - Check if cache server is available

### Lux::Template (`lib/lux/template/`)
Template rendering via Tilt:
- `Lux::Template.render(scope, template:, layout:)`
- `Lux::Template.helper(scope, :name)` - Create helper with module methods
- Supports HAML, ERB, and other Tilt formats
- Template caching enabled in production

### Lux::Mailer (`lib/lux/mailer/mailer.rb`)
Email sending:
- `Mailer.deliver(:template, *args)` - Render and deliver
- `Mailer.render(:template, *args)` - Get body only
- `Mailer.prepare(:template, *args).deliver` - Prepare then deliver
- `Mailer.template_name(*args).deliver` - Rails-style via method_missing
- Callbacks: `before`, `after`
- Template rendering in `./app/views/mailer/`
- Layout in `./app/views/mailer/layout.haml`

### Lux::Error (`lib/lux/error/error.rb`)
Error handling with HTTP status codes. Methods on `Lux.error`:
- `Lux.error.bad_request(msg)` - 400
- `Lux.error.unauthorized(msg)` - 401
- `Lux.error.payment_required(msg)` - 402
- `Lux.error.forbidden(msg)` - 403
- `Lux.error.not_found(msg)` - 404
- `Lux.error.method_not_allowed(msg)` - 405
- `Lux.error.not_acceptable(msg)` - 406
- `Lux.error.internal_server_error(msg)` - 500
- `Lux.error.not_implemented(msg)` - 501
- `Lux::Error.render(error)` - Error page rendering
- `Lux::Error.inline(object, msg)` - Inline error display
- `Lux::Error.format(error, opts)` - Format backtrace (supports `html:`, `message:`, `gems:`)

### Lux::Environment (`lib/lux/environment/environment.rb`)
Environment detection via `Lux.env`. Three valid environments: `development`, `production`, `test` (set via `RACK_ENV` or `LUX_ENV`):
- `Lux.env.development?` / `Lux.env.dev?` - True when NOT production (includes test)
- `Lux.env.production?` / `Lux.env.prod?` - True only in production
- `Lux.env.test?` - True in test or when run via rspec
- `Lux.env.web?` - True when running under Rack/Puma server
- `Lux.env.cli?` - True when NOT running as web server
- `Lux.env.rake?` - True when run via rake
- `Lux.env.live?` - True when `ENV['LUX_LIVE'] == 'true'`
- `Lux.env.local?` - Inverse of `live?`
- `Lux.env.reload?` - True when `LUX_ENV` includes `r` flag
- `Lux.env.log?` - True when `LUX_ENV` includes `l` flag
- `Lux.env == :dev` - Comparison operator

Note: `log` is a flag in `LUX_ENV`, not a separate environment mode. The `lux ss` command sets `LUX_ENV=le` (log + errors).

### Lux::Config (`lib/lux/config/config.rb`)
Configuration module. `Lux.config` returns a hash (with indifferent access) loaded from `config/config.yaml`:
- `Lux.config.key = value` / `Lux.config.key`
- `Lux.config.all` - Get all config

Default config values:
- `delay_timeout` - Background job timeout (3600 dev / 30 prod)
- `log_level` - Logger level (:info or :error)
- `logger_path_mask` - Log file path pattern (`'./log/%s.log'`)
- `logger_files_to_keep` - Log rotation count (3)
- `logger_file_max_size` - Max log file size (10,240,000)
- `use_autoroutes` - Enable template-based routes (false)
- `serve_static_files` - Static file serving (true)
- `asset_root` - Asset root path (false)
- `app_timeout` - Request timeout

Hooks:
- `Lux.config.on_reload_code { }` - Code reload hook
- `Lux.config.on_mail_send { |mail| }` - Mail send hook

Session config keys:
- `Lux.config[:session_cookie_name]`
- `Lux.config[:session_cookie_max_age]`
- `Lux.config[:session_forced_validity]`

### Lux::Plugin (`lib/lux/plugin/plugin.rb`)
Plugin management:
- `Lux.plugin(name_or_folder)` - Load a plugin
- `Lux.plugin(name:, folder:, namespace:)` - Load with options
- `Lux.plugin.get(:name)` - Get loaded plugin
- `Lux.plugin.loaded` - All loaded plugin values
- `Lux.plugin.keys` - Loaded plugin names
- `Lux.plugin.folders(namespace)` - Plugin folders by namespace

### Lux::Application::Render (`lib/lux/render/`)
Page and template rendering:
- `Lux.render(path, opts)` - Render full page
- `Lux.render.get(path, params, opts)` - GET request render
- `Lux.render.post(path, params, opts)` - POST request render
- `Lux.render.delete(...)` / `.patch(...)` / `.put(...)` - Other methods
- `Lux.render.controller('main#index')` - Render controller action directly
- `Lux.render.controller('main#index') { @var = value }` - With setup block
- `Lux.render.template(scope, template)` - Render template
- `Lux.render.cell(name, *args)` - Render ViewCell

## Ruby Core Extensions (`lib/overload/`)

18 files extending Ruby core classes:

### Object (`object.rb`, `blank.rb`, `boolean.rb`, `raise_variants.rb`)
- `obj.or(default)` - Return default if blank or zero
- `obj.try(:method)` - Safe method call (nil on NilClass)
- `obj.presence` - Return self if present, nil otherwise
- `obj.present?` / `obj.blank?` - Presence checks (defined for Object, NilClass, FalseClass, TrueClass, Array, Hash, Numeric, Time, String)
- `obj.is!(Type)` - Type assertion (raises on mismatch). Without arg checks presence
- `obj.is?(Type)` - Boolean type check (no raise)
- `obj.is_hash?`, `obj.is_array?`, `obj.is_string?`, `obj.is_numeric?`, `obj.is_symbol?`, `obj.is_boolean?`
- `obj.is_true?` / `obj.is_false?` - Truthy string check (`'true'`, `'on'`, `'1'`)
- `obj.to_b` - Convert to boolean
- `obj.andand(func)` - Safe chain (present? check)
- `obj.die(msg)` - Print error and raise
- `obj.instance_variables_hash` - Hash of instance variables
- `r(what)` - Raise with inspect/JSON (global)
- `rr(what)` - Console log dump with context (global)
- `LOG(what)` - Write to `./log/LOG.log` (global)
- `r?(obj)` / `m?(obj)` - Debug: list unique methods (global)

### String (`string.rb`)
- `str.constantize` / `str.constantize?` - Convert to constant
- `str.parameterize` / `str.to_url` - URL-safe string (max 50 chars)
- `str.to_slug(len)` - Slug format with hyphens
- `str.trim(len)` - Truncate with ellipsis
- `str.squish` - Collapse whitespace
- `str.html_escape` / `str.html_safe` / `str.html_unsafe` - HTML encoding
- `str.as_html` - Simple markdown (newlines to `<br>`, URLs to links)
- `str.sanitize` / `str.quick_sanitize` - HTML sanitization
- `str.sha1` / `str.md5` - Hash digests
- `str.wrap(:tag, opts)` - Wrap in HTML tag
- `str.escape` / `str.unescape` - URL encoding
- `str.colorize(:color)` / `str.decolorize` - ANSI terminal colors
- `str.first` / `str.last(n)` - Character access
- `str.qs_to_hash` - Parse query string to hash
- `str.attribute_safe` / `str.db_safe` - Safe strings
- `str.fix_ut8` - Fix invalid UTF-8
- `str.parse_erb(scope)` - Parse as ERB template
- `str.extract_scripts!` - Extract `<script>` tags
- `str.remove_tags` - Strip HTML tags
- `str.string_id` - Decode StringBase ID

### Hash (`hash.rb`)
- `hash.to_query` - Convert to URL query string
- `hash.to_attributes` - Convert to HTML attributes
- `hash.to_css` - Convert to CSS inline style
- `hash.deep_sort` - Recursively sort keys
- `hash.pluck(*keys)` - Select specific keys
- `hash.remove_empty` - Remove blank entries
- `hash.deep_compact` - Recursively remove empty values
- `hash.to_js(opts)` - JSON without quoted keys
- `hash.html_safe(key)` - HTML-safe value at key

Note: `hash.to_hwia` is provided by the `hash_wia` gem, not the overload files.

### Array (`array.rb`)
- `array.to_csv` - Convert to CSV (semicolon-delimited)
- `array.to_sentence(opts)` - Rails-like sentence join
- `array.toggle(el)` - Toggle element presence
- `array.to_ul(class)` - Convert to HTML list
- `array.wrap(tag, opts)` - Wrap each element in HTML tag
- `array.last=` - Set last element
- `array.random_by_string(str)` - Deterministic element for string
- `array.xuniq` - Unique non-blank elements
- `array.shift_push` - Round-robin shift
- `array.xmap` - Map with 1-based counter

### Integer (`integer.rb`)
- `int.pluralize(:noun)` - Smart pluralization (`0.pluralize(:cat)` -> `"no cats"`)
- `int.dotted` - Dot-separated thousands (`1234567` -> `"1.234.567"`)
- `int.to_filesize` - Human-readable file size
- `int.string_id` - Encode to StringBase short string

### Float (`float.rb`)
- `float.as_currency(opts)` - Currency formatting (European style)
- `float.format_with_underscores` - Underscore thousands
- `float.dotted(round)` - Dot-thousands, comma-decimal

### Dir (`dir.rb`)
- `Dir.folders(dir)` - List subdirectories
- `Dir.files(dir, opts)` - List files
- `Dir.find(dir, opts)` - Deep file search with filtering
- `Dir.require_all(folder)` - Require all `.rb` files recursively
- `Dir.mkdir?(name)` - Create directory path

### Other Extensions
- `Class#descendants(fast)` - All descendant classes (`class.rb`)
- `Class#source_location` - Source file path (`class.rb`)
- `File.write_p`, `File.append`, `File.ext`, `File.delete?`, `File.is_locked?` (`file.rb`)
- `Pathname#touch`, `Pathname#write_p`, `Pathname#folders`, `Pathname#files` (`pathname.rb`)
- `Struct#to_hash` (`struct.rb`)
- `Time#short`, `Time#long`, `Time#current`, `Time.speed`, `Time.ago`, `Time.agop`, `Time.monotonic`, `Time.for` (`time.rb`)
- `Date#to_i` (`time.rb`)
- `NilClass#empty?`, `NilClass#is?` (`nil.rb`)
- `Thread::Simple` - Thread pool (`thread_simple.rb`)
- `Hash#to_jsons`, `Hash#to_jsonp`, `Hash#to_jsonc`, `Array#to_jsons`, etc. (`json.rb`)

## Common Utilities (`lib/common/`)

### Crypt (`lib/common/crypt.rb`)
- `Crypt.encrypt(data, ttl:, password:)` - JWT encryption (HS512)
- `Crypt.decrypt(token, password:, unsafe:)` - JWT decryption
- `Crypt.short_encrypt(data, ttl)` / `Crypt.short_decrypt(data)` - Lightweight Base64 encoding
- `Crypt.simple_encode(str)` / `Crypt.simple_decode(str)` - Base64 + ROT13 (JS interop)
- `Crypt.sha1(str)` / `Crypt.md5(str)` - Salted hash digests
- `Crypt.sha1s(str)` - Shorter SHA1 (base-36)
- `Crypt.uid(size)` - Random alphanumeric (default 32 chars)
- `Crypt.random(length)` - Random string (no ambiguous chars)
- `Crypt.bcrypt(plain, check)` - BCrypt password hashing
- `Crypt.base64(str)` - URL-safe Base64
- `Crypt.secret` - Secret from ENV or config

### StringBase (`lib/common/string_base.rb`)
Obfuscated ID encoding:
- `StringBase.encode(int)` / `StringBase.decode(str)` - Default short encoding
- `StringBase.short` / `StringBase.medium` / `StringBase.long` - Different key sets
- `StringBase.uid` - Time-based unique ID
- `StringBase#extract(url_part)` - Extract ID from URL segment

### StructOpts (`lib/common/struct_opts.rb`)
- `StructOpts(vars, opts)` - Create Struct from hash with defaults

### TimeDifference (`lib/common/time_difference.rb`)
- `TimeDifference.new(start, end).humanize` - Human-readable time difference

## Routing Patterns

Routes are defined in `Lux.app` block:

```ruby
Lux.app do
  before { }           # Before all requests

  routes do
    root 'main#index'  # Root path

    # Simple mapping
    map about: 'main#about' if get?

    # Namespace mapping
    map 'admin' do
      root 'admin/dashboard#index'
      map users: 'admin/users'
    end

    # Dynamic routes
    map '/users/:id' => 'users#show'

    # Block-based request type check
    post? do
      map api: :api_router
    end
  end

  after { }            # After all requests
  rescue_from { |e| }  # Error handling
end
```

## Controller Patterns

```ruby
class UsersController < ApplicationController
  layout :application
  # template_root './app/views' # default

  before { @user = User.current }
  before_action { |action| authorize!(action) }

  mock :show  # Empty action, just renders template

  def index
    @users = User.all
    # Renders ./app/views/users/index.haml
  end

  def show
    render json: @user
  end

  def transfer
    action :baz                  # Transfer to :baz action
    action 'another/foo#bar'     # Transfer to Another::FooController#bar
  end

  def action_missing(name)
    # Custom fallback for missing actions
    super  # Default: look for template
  end
end
```

Render options:
```ruby
render text: 'foo'
render plain: 'foo'
render html: '<html>...'
render json: {}
render javascript: '...'
render template: './some/template.haml', data: @data
render template: false, content_type: :text
```

## Testing

Run tests with RSpec:
```bash
bundle exec rspec
bundle exec rspec spec/lux_tests/routes_spec.rb
```

Test files are in `spec/lux_tests/` and `spec/lib_tests/`.

## CLI Commands

```bash
lux server       # Start web server (aliases: s, ss, silent)
lux console      # Start Pry console (alias: c)
lux evaluate     # Eval ruby string in Lux context (alias: e)
lux get /path    # Fetch single page by path
lux config       # Show configuration
lux generate     # Generate models, cells, controllers
lux secrets      # Display ENV and secrets
lux stats        # Print project statistics
lux new APP      # Create new Lux application
lux benchmark    # Benchmark app boot time
lux cerb         # Parse .cerb (CLI ERB) templates
lux memory       # Profile memory usage
lux plugin       # Show loaded plugins
lux sysd         # Systemd service management
lux template     # Parse file with ENV variable substitution
```

## Rake Tasks

```bash
rake db:am              # Auto-migrate schema
rake db:backup[name]    # Dump databases to SQL
rake db:restore[name]   # Restore from SQL dump
rake db:drop            # Drop and recreate databases
rake db:test            # Create test database copies
rake db:seed            # Drop, migrate, and seed
rake db:gen_seeds       # Generate seed code from data
rake db:console         # Open psql console
rake assets:auto        # Auto-compile assets
rake job_runner:start   # Start job runner
rake job_runner:web     # Start job runner web UI
rake exceptions         # List logged exceptions
rake exceptions:clear   # Clear exception logs
```

## Important Patterns for Agents

1. **Request Context**: Always access via `Lux.current` or `current` helper
2. **Response Flow**: Set `response.body` to stop processing
3. **Routing**: Response body being set halts route processing
4. **Caching**: Use `Lux.cache.fetch` for computed values
5. **Templates**: Default location is `./app/views/{controller}/{action}.haml`
6. **Layouts**: Found in `./app/views/layouts/` or `./app/views/{name}/layout.haml`
7. **Helpers**: Named `{Name}Helper` modules in `./app/helpers/`
8. **Environment**: `development?` returns true for both dev AND test environments
9. **Secrets**: `Lux.secrets` is an alias for `Lux.config`
10. **ViewCell**: Provided by external `view-cell` gem, not a local directory

## Configuration Files

- `./config/environment.rb` - Main boot file
- `./config/application.rb` - Application setup
- `./config/config.yaml` - YAML configuration (default + per-environment)
- `./config/secrets.yaml` - Encrypted secrets
- `./app/routes.rb` - Route definitions

## Dependencies

Key gems (from gemspec):
- `rack` - Web server interface
- `sequel_pg` - PostgreSQL ORM
- `haml` - Template engine (pulls in `tilt` transitively)
- `jwt` - Session encryption
- `mail` - Email sending
- `hash_wia` - Hash with indifferent access
- `class-callbacks` - Callback system
- `class-cattr` - Class attributes
- `view-cell` - ViewCell components
- `as-duration` - Duration helpers (e.g., `5.minutes`)
- `deep_merge` - Config loading
- `thor` - CLI framework
- `pry` - Console
- `rake` - Task runner
- `dotenv` - Environment variables
- `typero` - Type schemas
- `amazing_print` - Debug output
- `niceql` - SQL formatting
- `whirly` - CLI spinner
- `tty-prompt` - Interactive terminal prompts
