# Lux::Application - agent guide

Router + request lifecycle. Lifecycle callbacks at the top of
`Lux do ... end`; routing DSL inside a `routes do ... end` block.

## Canonical example

```ruby
Lux.app do
  # helper methods become instance methods on the application
  def api_router
    Lux::Api.call nav.path
  end

  # lifecycle callbacks live at the top level of `Lux.app do`
  before do
    nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
  end

  after do
    # post-render hook: mutate body, tweak headers, audit-log, ...
  end

  rescue_from do |err|
    call '%s#error' % [user ? :main : :promo]
  end

  # all routing DSL goes inside `routes do ... end`
  routes do
    root 'main'
    map about: 'static#about' if get?
    post? { map api: :api_router }
    map '/foo/:bar/baz' => 'main#foo'
    map 'boards'
    map 'admin' do
      root 'admin/dashboard'
      map 'users', 'admin/users'
    end
    map '/api' => ApiApp                     # any class responding to .call(env)
  end
end
```

## Rules

* **Routing DSL lives inside `routes do ... end`.** `map`, `root`,
  `match`, `subdomain`, `favicon`, `plugin_route`, `plugin_routes`,
  `get?`/`post?`/... all belong inside the routes block. The framework
  technically supports them at the top level too (singleton DSL
  wrappers), but every real app keeps routing inside `routes do` for
  clarity and so runtime conditionals can interleave naturally.
* **`map` matches and advances the cursor.** `call` dispatches
  unconditionally - use inside `rescue_from`.
* **Id canonicalization happens in a `before` filter:**
  `nav.path(:ref) { |el| ... }` rewrites id-like segments to the `:ref`
  symbol so resourceful action resolution can do its job.
* **Method-predicate scope:** `post? { map ... }` only applies the block
  on POST. Same for other verbs.
* **Helper defs at top level** (like `def api_router`) become instance
  methods on the Application and are callable as targets via `:symbol`.
* **`call :symbol`** = dynamic dispatch (recorded as `[dynamic]` by
  `lux routes`). Cannot be statically inspected.
* **`rescue_from`** wins over controller `:error` actions. Used to
  forward errors via `map` / `call`. The block is `instance_exec`'d so
  the full routing DSL is available.
* **Subdomain matching:** `subdomain 'admin' do ... end` only enters the
  block when `nav.subdomain == 'admin'`.
* **No `mount`. Use `map`.** Any class responding to `.call(env)` is a
  Rack app. Route it the same way as a controller:
  `map '/api' => ApiApp` (absolute path) or `map api: ApiApp` (symbol).
  Lux invokes `ApiApp.call(Lux.current.env)` and renders the Rack
  response - `SCRIPT_NAME` is **not** rewritten, the app sees the full
  path. Rails users: `mount Foo, at: '/x'` -> `map '/x' => Foo`.
* **`before` / `after` callbacks** at the top level fire on every
  request. `before` runs pre-routing (use for nav canonicalization,
  auth lookup); `after` runs post-render (use for body transforms,
  header tweaks based on the final response). Both are top-level
  DSL - no wrapper needed.

## Don't

* Don't put expensive work in routing DSL evaluation - top-level DSL is
  class-eval'd once at boot, but `before`/`routes` blocks run per-request.
* Don't mutate `nav.path` in routing - use `lux.route` as the cursor. Nav
  is the canonical request path.
* Don't forget to override `:error` on whatever controller serves errors
  (most apps do this on `ApplicationController`). The default Lux error
  page is functional but bare.

## See also

* [`Lux::Controller` AGENTS](../controller/AGENTS.md) - dispatch target
* [`Lux::Current` AGENTS](../current/AGENTS.md) - `nav`, `route`, params
* [`Lux::Error` AGENTS](../error/AGENTS.md) - `Lux.error.not_found` etc.
