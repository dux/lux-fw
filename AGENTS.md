# Lux Framework - AI Agent Guidelines

This document provides comprehensive guidance for AI agents working with the Lux web framework codebase.

## Framework Overview

Lux is a lightweight, Rack-based Ruby web framework designed for speed and simplicity. It provides a Rails-like interface with Sinatra-like performance.

**Key characteristics:**
- Rack-based architecture
- Explicit over magic approach
- JWT-based encrypted sessions
- HAML/ERB template support via Tilt
- PostgreSQL ORM via Sequel

## Project Structure

```
lux-fw/
├── bin/cli/           # CLI commands (server, console, generate, etc.)
├── lib/
│   ├── lux/           # Core framework modules
│   │   ├── application/   # Router and request handling
│   │   ├── cache/         # Caching (memory, memcached, sqlite)
│   │   ├── config/        # Configuration management
│   │   ├── controller/    # Request controllers
│   │   ├── current/       # Request context (session, cookies, params)
│   │   ├── environment/   # Environment detection
│   │   ├── error/         # Error handling and HTTP status codes
│   │   ├── mailer/        # Email sending via mail gem
│   │   ├── plugin/        # Plugin system
│   │   ├── render/        # Page/template rendering
│   │   ├── response/      # HTTP response, flash, file serving
│   │   └── template/      # Template engine via Tilt
│   ├── overload/      # Ruby core class extensions
│   ├── common/        # Utilities (Crypt, StringBase, etc.)
│   └── loader.rb      # Framework loader
├── misc/demo/         # Demo application
├── plugins/           # Framework plugins
├── spec/              # RSpec tests
└── tasks/             # Rake tasks
```

## Core Components

### Lux Module (`lib/lux/lux.rb`)
Main entry point providing:
- `Lux.root` - Application root path
- `Lux.fw_root` - Framework root path
- `Lux.call(env)` - Main Rack entry point
- `Lux.speed { }` - Block execution timing
- `Lux.delay { }` - Background thread execution
- `Lux.log` - Logging helper

### Lux::Application (`lib/lux/application/`)
Router and request lifecycle:
- Callbacks: `before`, `routes`, `after`, `rescue_from`
- Routing methods: `root`, `map`, `call`, `match`, `test?`
- Request method helpers: `get?`, `post?`, `delete?`, etc.
- Nav object for URL parsing and manipulation

### Lux::Controller (`lib/lux/controller/controller.rb`)
Request controllers with Rails-like interface:
- Callbacks: `before`, `before_action`, `before_render`, `after`
- Class attributes: `layout`, `template_root`, `helper`
- Instance methods: `render`, `redirect_to`, `send_file`, `flash`
- `action_missing` - Called when action not found; default looks for matching template
- `mock :action` - Create empty action for template-only rendering

### Lux::Current (`lib/lux/current/`)
Thread-local request context accessible via `Lux.current` or `current`:
- `current.request` - Rack request
- `current.response` - Lux response
- `current.session` - JWT-encrypted session
- `current.nav` - URL navigation helper
- `current.params` - Request parameters
- `current.var` - Request-scoped variables
- `current.cache(key) { }` - Request-scoped caching

### Lux::Response (`lib/lux/response/response.rb`)
HTTP response handling:
- `response.body` - Set/get response body
- `response.status` - HTTP status code
- `response.header(key, value)` - Set headers
- `response.redirect_to(path)` - Redirect with flash support
- `response.send_file(path)` - File downloads
- `response.flash` - Flash messages (info, error, warning)
- `response.etag` - ETag caching
- `response.max_age` - Cache-Control header

### Lux::Cache (`lib/lux/cache/cache.rb`)
Caching with multiple backends:
- `Lux.cache.server = :memory | :memcached | :sqlite`
- `Lux.cache.fetch(key, ttl:) { }` - Fetch or compute
- `Lux.cache.read(key)` / `Lux.cache.write(key, data)`
- `Lux.cache.generate_key(*args)` - Key generation from objects

### Lux::Template (`lib/lux/template/`)
Template rendering via Tilt:
- `Lux::Template.render(scope, template:, layout:)`
- Helper module with `render`, `content`, `cache`, `flash`
- Supports HAML, ERB, and other Tilt formats

### Lux::Mailer (`lib/lux/mailer/mailer.rb`)
Email sending:
- `Mailer.prepare(:template, *args).deliver`
- `Mailer.render(:template, *args)` - Get body only
- Callbacks: `before`, `after`
- Template rendering in `./app/views/mailer/`

### Lux::Error (`lib/lux/error/error.rb`)
Error handling with HTTP status codes:
- `Lux.error.not_found(message)`
- `Lux.error.forbidden(message)`
- `Lux.error.unauthorized(message)`
- `Lux::Error.render(error)` - Error page rendering

### Lux::Environment (`lib/lux/environment/environment.rb`)
Environment detection via `Lux.env`:
- `Lux.env.development?` / `Lux.env.dev?`
- `Lux.env.production?` / `Lux.env.prod?`
- `Lux.env.test?`
- `Lux.env.web?` / `Lux.env.cli?`
- `Lux.env.show_errors?`, `Lux.env.reload_code?`, `Lux.env.screen_log?`

### Lux::Config (`lib/lux/config/config.rb`)
Configuration via `Lux.config`:
- `Lux.config.key = value`
- `Lux.config.on_reload_code { }` - Code reload hook
- `Lux.config.on_mail_send { |mail| }` - Mail hook
- `Lux.config.error_logger` - Error logging proc
- `Lux.config.use_autoroutes` - Enable template-based routes
- `Lux.config.serve_static_files` - Static file serving

## Ruby Core Extensions (`lib/overload/`)

### Object
- `obj.or(default)` - Return default if blank
- `obj.try(:method)` - Safe method call
- `obj.is!(Type)` - Type assertion
- `obj.present?` / `obj.blank?`
- `obj.is_hash?`, `obj.is_array?`, `obj.is_numeric?`

### String
- `str.constantize` - Convert to constant
- `str.parameterize` / `str.to_url` - URL-safe string
- `str.trim(len)` - Truncate with ellipsis
- `str.html_escape` / `str.html_safe`
- `str.sha1` / `str.md5`
- `str.wrap(:tag, opts)` - Wrap in HTML tag

### Hash
- `hash.to_hwia` - Hash with indifferent access
- `hash.slice(*keys)` / `hash.except(*keys)`
- `hash.deep_compact` - Remove empty values recursively
- `hash.to_query` - Convert to query string

### Array
- `array.to_sentence` - Join with "and"
- `array.toggle(el)` - Toggle element presence
- `array.to_ul(class)` - Convert to HTML list

## Routing Patterns

Routes are defined in `Lux.app` block:

```ruby
Lux.app do
  before { }           # Before all requests

  routes do
    root 'main#index'  # Root path

    # Simple mapping
    map.about 'main#about' if get?

    # Namespace mapping
    map 'admin' do
      root 'admin/dashboard#index'
      map.users 'admin/users'
    end

    # Dynamic routes
    map '/users/:id' => 'users#show'

    # Proc routes
    map.api proc { [200, {}, ['OK']] }
  end

  after { }            # After all requests
  rescue_from { |e| }  # Error handling
end
```

## Controller Patterns

```ruby
class UsersController < ApplicationController
  layout :application
  template_root './app/views'

  before { @user = User.current }
  before_action { |action| authorize!(action) }

  def index
    @users = User.all
    # Renders ./app/views/users/index.haml
  end

  def show
    render json: @user
  end

  def action_missing(name)
    # Custom fallback for missing actions
    super  # Default: look for template
  end
end
```

## Common Utilities

### Crypt (`lib/common/crypt.rb`)
- `Crypt.encrypt(data, ttl:, password:)` - JWT encryption
- `Crypt.decrypt(token)` - JWT decryption
- `Crypt.sha1(str)` / `Crypt.md5(str)`
- `Crypt.uid(size)` - Random alphanumeric
- `Crypt.bcrypt(plain, check)` - Password hashing

### Session (`lib/lux/current/lib/session.rb`)
JWT-encrypted cookie session:
- `session[:key]` - Get/set values
- Automatic security checks (IP/browser change)
- Configurable via `Lux.config.session_*`

## Testing

Run tests with RSpec:
```bash
bundle exec rspec
bundle exec rspec spec/lux_tests/routes_spec.rb
```

## CLI Commands

```bash
lux server      # Start web server
lux console     # Start console
lux generate    # Generate models, cells
lux get /path   # Fetch single page
lux routes      # Print routes
lux config      # Show configuration
lux secrets     # Manage secrets
```

## Important Patterns for Agents

1. **Request Context**: Always access via `Lux.current` or `current` helper
2. **Response Flow**: Set `response.body` to stop processing
3. **Routing**: Use `throw :done` to halt route processing
4. **Caching**: Use `Lux.cache.fetch` for computed values
5. **Templates**: Default location is `./app/views/{controller}/{action}.haml`
6. **Layouts**: Found in `./app/views/layouts/` or `./app/views/{name}/layout.haml`
7. **Helpers**: Named `{Name}Helper` modules in `./app/helpers/`

## Configuration Files

- `./config/environment.rb` - Main boot file
- `./config/application.rb` - Application setup
- `./config/config.yaml` - YAML configuration (default + per-environment)
- `./config/secrets.yaml` - Encrypted secrets
- `./app/routes.rb` - Route definitions

## Dependencies

Key gems:
- `rack` - Web server interface
- `sequel_pg` - PostgreSQL ORM
- `haml` - Template engine
- `jwt` - Session encryption
- `mail` - Email sending
- `tilt` - Template abstraction
- `hash_wia` - Hash with indifferent access
- `class-callbacks` - Callback system
