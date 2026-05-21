# Lux::Application

Main router and request lifecycle. Lifecycle callbacks
(`before`/`after`/`rescue_from`) live at the top level of
`Lux do ... end`; all routing DSL (`map`, `root`, ...) lives inside the
`routes do ... end` block.

## Small example

```ruby
# config.ru
require 'lux-fw'

Lux do
  before do
    nav.path(:ref) { |el| el =~ /\A\d+\z/ ? el : nil }
  end

  # post-render: expand T[key.path] placeholders to real translations
  after do
    response.body { |b| b.gsub(/T\[([\w.]+)\]/) { Translation.fetch($1) } }
  end

  rescue_from do |err|
    call 'main#error'                  # forwards to MainController#error
  end

  routes do
    root 'main'                        # / -> MainController#root
    map about: 'static#about'          # /about -> Static#about
    map 'users'                        # /users -> UsersController (resourceful)
  end
end
```

`Lux do ... end` (inside Rack) class-evals into `Lux::Application`, mounts
as the Rack app, and prints the start banner. For specs use
`Lux.app do ... end` (no Rack registration).

## Full example

```ruby
Lux.app do
  # --- helpers (instance methods, callable from routes)
  def api_router
    Lux.error.forbidden if Lux.env.prod? && !post?
    Lux::Api.call nav.path
  end

  # --- request callbacks (top level)
  before do
    nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
  end
  after { }

  # --- error sink (always wins when present; defaults to controller :error)
  rescue_from do |err|
    call '%s#error' % [user ? :main : :promo]
  end

  # --- routes ---------------------------------------------------------
  routes do
    root 'main'                                    # /
    map about: 'static#about' if get?              # /about (GET only)

    post? { map api: :api_router }                 # POST scope block

    map '/foo/:bar/baz' => 'main#foo'              # absolute path with capture

    map 'boards'                                   # resourceful BoardsController
    map [:array1, :array2] => 'root'               # multi-key map
    map %r{^@} => [UsersController, :show]         # regex match

    subdomain 'admin' do
      map 'users', 'admin/users'                   # admin.host/users
    end

    map 'admin' do                                 # nested scope
      root 'admin/dashboard'                       # /admin
      map users: 'admin/users'                     # /admin/users
      map 'reports#monthly'                        # /admin/reports -> #monthly
    end

    mount ApiApp => '/api'                         # Rack app mount
    favicon 'app/assets/favicon.ico'
    plugin_route :authcog                          # explicit single plugin
    plugin_routes                                  # auto-mount every plugin with routes.rb
  end
end
```

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

After `nav.path(:ref) { ... }` canonicalizes id segments to `:ref`:

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

`nav.path` is the canonical request path. `lux.route` is the per-request
cursor over it; `map` advances the cursor without mutating nav.

* `lux.route.path`     - remaining path after consumed segments
* `lux.route.root`     - first remaining segment
* `lux.route.child`    - second remaining segment
* `lux.route.consumed` - segments before the cursor
* `lux.route.with_scope(n) { ... }` - internal (used by `map`)

## Class filters

```ruby
config { ... }      # pre-boot
boot   { ... }      # after rack app boot (web only)
before { ... }      # before every request
routes { ... }      # legacy block form
after  { ... }      # after every request
```

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
* [`AGENTS.md`](./AGENTS.md) - LLM guide
