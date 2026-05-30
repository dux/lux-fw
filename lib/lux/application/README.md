# Lux::Application

Main router and request lifecycle. Lifecycle callbacks
(`before`/`after`/`rescue_from`) live at the top level of
`Lux do ... end`. The routing DSL (`map`, `root`, `match`, `subdomain`,
`get?`, ...) works **both** at the top level of `Lux do ... end` and
inside an optional `routes do ... end` block - neither form is required.
The two forms interleave by source order, so you can mix top-level routes
and `routes do` blocks freely.

`Lux do ... end` (inside Rack / `config.ru`) class-evals into
`Lux::Application`, mounts as the Rack app, and prints the start banner.
For specs use `Lux.app do ... end` (no Rack registration).

## Full example

```ruby
# config.ru
require 'lux-fw'

Lux.app do
  # --- class-level filters ------------------------------------------------
  config { ... }                                # pre-boot
  boot   { ... }                                # after rack app boot (web only)

  # --- helpers (instance methods, callable from routes) -------------------
  def api_router
    Lux.error.forbidden if Lux.env.prod? && !post?
    Lux::Api.call nav.path
  end

  # --- request callbacks (top level; instance_exec'd on Application) ------
  before do
    nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
  end
  after do
    response.body { |b| b.gsub(/T\[([\w.]+)\]/) { Translation.fetch($1) } }
  end

  # --- error sink (always wins when present; default falls back to
  #     active controller's :error action) ---------------------------------
  rescue_from do |err|
    call '%s#error' % [user ? :main : :promo]
  end

  # --- routes (top level; an optional `routes do ... end` wrapper also
  #     works and interleaves with these by source order) -----------------
  root 'main'                                    # /          -> MainController#root
  map about: 'static#about' if get?              # /about     (GET only)
  map 'users'                                    # resourceful UsersController

  post? { map api: :api_router }                 # POST scope block

  map '/foo/:bar/baz' => 'main#foo'              # absolute path with capture
  map [:array1, :array2] => 'root'               # multi-key map
  map %r{^@} => [UsersController, :show]         # regex match

  map 'boards' do
    root 'boards/index'                          # /boards
    map favorites: 'boards#favorites'            # /boards/favorites
  end

  subdomain 'admin' do
    map 'users', 'admin/users'                   # admin.host/users
  end

  map 'admin' do                                 # nested scope
    root 'admin/dashboard'                       # /admin
    map users: 'admin/users'                     # /admin/users
    map 'reports#monthly'                        # /admin/reports -> #monthly
  end

  map '/api'           => ApiApp                 # any Rack-callable class
  map '/admin/sys/jobs' => LuxJobWeb             # deep absolute path
  call '/api'          => ApiApp                 # unconditional (for rescue_from etc.)

  plugin_route :web_common                       # explicit single plugin
  plugin_routes                                  # auto-mount every plugin with routes.rb

  # Equivalent, wrapped in the optional block - mix and match as you like:
  #
  #   routes do
  #     root 'main'
  #     map 'users'
  #   end
end
```

## Mounting Rack apps (no `mount` keyword)

Any class responding to `.call(env)` - Rack, Sinatra, Roda, a plain class
with `self.call(env)` - is a valid target for `map` / `call`. When the
path matches, Lux calls `target.call(Lux.current.env)` and renders the
returned `[status, headers, body]` tuple. `SCRIPT_NAME` is **not**
rewritten - the mounted app sees the full path; wrap it with
`Rack::URLMap` (or strip inside the app) if it needs a prefix.

Coming from Rails:

| Rails                                  | Lux                                |
|----------------------------------------|------------------------------------|
| `mount Foo, at: '/x'`                  | `map '/x' => Foo`                  |
| `mount Sidekiq::Web => '/admin/jobs'`  | `map '/admin/jobs' => Sidekiq::Web`|
| `mount Foo => '/x'` (Rails 7+)         | `map '/x' => Foo`                  |

## `map` vs `call`

| Form | Match check | Dispatch |
|------|-------------|----------|
| `map 'foo'`             | match `/foo` | `FooController`, resourceful |
| `map 'foo#bar'`         | match `/foo` | `FooController#bar` explicit |
| `map 'a', 'foo'`        | match `/a`   | `FooController`, resourceful |
| `map a: 'foo'`          | match `/a`   | `FooController`, resourceful |
| `map 'foo' do ... end`  | match `/foo` | enter scope, block at request time |
| `map '/abs/:var' => 'foo#bar'` | absolute path with capture | explicit |
| `map [:foo, :bar] => 'root'` | match either | `RootController` |
| `call 'foo#bar'`        | none (unconditional) | explicit |
| `call -> { [200, {}, ['OK']] }` | none | return Rack tuple |

## Resourceful action resolution

After `nav.path(:ref) { ... }` canonicalises id segments to `:ref`:

| URL                        | Action       | `nav.ref` |
|----------------------------|--------------|-----------|
| `/boards`                  | `:root`      | nil       |
| `/boards/edit`             | `:edit`      | nil       |
| `/boards/new`              | `:new`       | nil       |
| `/boards/123`              | `:show_ref`  | "123"     |
| `/boards/123/edit`         | `:edit_ref`  | "123"     |
| `/boards/users/123/edit`   | `:edit_ref`  | "123"     |
| `/boards/foo/bar`          | `:foo`       | nil       |
| `/boards/123/foo/bar`      | `:foo_ref`   | "123"     |

Rules: empty remaining → `:root`. Only `:ref` → `:show_ref`. 2+ segments
→ first non-`:ref` after position 0. Any `:ref` in remaining → append
`_ref` to the action name.

## Route cursor

`nav.path` is the canonical request path; `lux.route` is the per-request
cursor over it. `map` advances the cursor without mutating nav.

* `lux.route.path`     - remaining path after consumed segments
* `lux.route.root`     - first remaining segment
* `lux.route.child`    - second remaining segment
* `lux.route.consumed` - segments before the cursor
* `lux.route.with_scope(n) { ... }` - internal (used by `map`)

## Error handling

Errors anywhere in the routing/action pipeline are caught by
`render_error`. Resolution order:

1. `rescue_from { |err| ... }` if defined on the app (always wins)
2. Active controller's `:error` action (every controller inherits a default)
3. `Lux::Error.render` (last-resort framework page)

The `:error` action receives `@error` (exception) and `@status` (resolved
HTTP code) as ivars. Override per controller for custom rendering.

## CLI

```bash
lux routes          # print the mounted route tree (shadow-executor)
lux routes -v       # add source location per entry
```

## See also

* [`../controller/README.md`](../controller/README.md) - actions
* [`../current/README.md`](../current/README.md) - `nav`, `route`, request state
* [`../response/README.md`](../response/README.md) - response builder
