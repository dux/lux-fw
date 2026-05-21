# Lux::Application - agent guide

Router + request lifecycle. Top-level DSL inside `Lux do ... end`.

## Canonical example

```ruby
Lux do
  def api_router
    Lux::Api.call nav.path
  end

  before do
    nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
  end

  rescue_from do |err|
    call '%s#error' % [user ? :main : :promo]
  end

  root 'main'
  map about: 'static#about' if get?
  post? { map api: :api_router }
  map '/foo/:bar/baz' => 'main#foo'
  map 'boards'
  map 'admin' do
    root 'admin/dashboard'
    map 'users', 'admin/users'
  end
  mount ApiApp => '/api'
end
```

## Rules

* **Top-level DSL works directly.** No need for a `routes do` wrapper -
  `map`, `root`, `match`, `subdomain`, `mount`, `favicon`, `plugin_route`,
  `get?`/`post?`/... all register at the top level of `Lux do`. Use
  `routes do` only for runtime conditionals as a single block.
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
* **Mount Rack apps** with `mount Rack::App => '/prefix'`.

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
