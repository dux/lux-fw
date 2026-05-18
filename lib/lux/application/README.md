## Lux.app (Lux::Application)

Main application controller and router.

* catches errors and dispatches to the active controller's `:error` action — every controller inherits a default one from `Lux::Controller`; override on any controller (e.g. `MainController#error`, `Api::BaseController#error`) for custom rendering
* calls `before`, `routes`, and `after` class filters on every request
* `map`, `root`, `match`, `subdomain`, `mount`, `favicon`, `plugin_route`, and the HTTP-method predicates work at the top level of `Lux.app do ... end` — no `routes do` wrapper required. `routes do ... end` is still supported when a single block is needed for runtime conditionals.

```ruby
Lux.app do

  def api_router
    Lux.error.forbidden 'Only POST requests are allowed' if Lux.env.prod? && !post?
    Lux::Api.call nav.path
  end

  before do
    check_subdomain
    nav.path(:ref) { |el| Ulid.is?(el.split('-').last) ? el.split('-').last : nil }
  end

  rescue_from do |err|
    call '%s#error' % [user ? :main : :promo]
  end

  ###

  root 'main'                          # / -> MainController#root
  map about: 'static#about' if get?    # /about (GET only)

  post? do                             # POST-only block
    map api: :api_router
  end

  map '/foo/:bar/baz' => 'main#foo'    # absolute path match, :bar captured

  map 'boards'                         # /boards -> BoardsController, resourceful
  map 'users'                          # /users  -> UsersController, resourceful

  map 'admin' do                       # scope at /admin
    map 'users', 'admin/users'         # /admin/users -> Admin::UsersController
    map 'reports#monthly'              # /admin/reports -> Admin::Reports#monthly
  end
end
```

#### map vs call

`map` always checks whether the route matches before dispatching. `call`
dispatches unconditionally (used inside `rescue_from` blocks).

* `map 'foo'`              - match /foo, resourceful dispatch to FooController
* `map 'foo#bar'`          - match /foo, explicit dispatch to FooController#bar
* `map 'a', 'foo'`         - match /a, resourceful dispatch to FooController
* `map a: 'foo'`           - same as above (hash form)
* `map a: :foo`            - same as above (symbol target)
* `map 'foo' do ... end`   - match /foo, enter scope (block runs at request time)
* `map '/abs/:var' => 'foo#bar'` - absolute path match with capture
* `map [:foo, :bar] => 'root'`   - match either
* `call 'foo'`             - unconditional resourceful dispatch
* `call 'foo#bar'`         - unconditional explicit dispatch
* `call [Foo, :bar]`       - unconditional dispatch via class+symbol
* `call -> { [200, {}, ['OK']] }` - return Rack tuple directly

#### Resourceful action resolution

After `nav.path(:ref) { ... }` canonicalizes ID segments to `:ref`:

| URL                         | action      | nav.ref |
|-----------------------------|-------------|--------|
| `/boards`                   | `:root`     | nil    |
| `/boards/edit`              | `:edit`     | nil    |
| `/boards/new`               | `:new`      | nil    |
| `/boards/123`               | `:show_ref` | "123"  |
| `/boards/123/edit`          | `:edit_ref` | "123"  |
| `/boards/users/123/edit`    | `:edit_ref` | "123"  |
| `/boards/foo/bar`           | `:foo`      | nil    |
| `/boards/123/foo/bar`       | `:foo_ref`  | "123"  |

Rules: empty remaining → `:root`. Only `:ref` → `:show_ref`. 2+ segments → first
non-`:ref` after position 0. Any `:ref` in the remaining path → append `_ref`.

Controllers declare ref-bearing actions in a `ref do ... end` block — each
`def NAME` inside becomes `NAME_ref`. Template lookup probes `show_ref.haml`
first and falls back to `show.haml`, so you can share a single template or
ship a dedicated ref-only one without renaming the action.

```ruby
class BoardsController < Lux::Controller
  def root          # /boards
    @boards = Board.all
  end

  def archive       # /boards/archive
  end

  ref do
    def show        # /boards/123          -> :show_ref
      @board = Board.find(nav.ref)
    end

    def edit        # /boards/123/edit     -> :edit_ref
      @board = Board.find(nav.ref)
    end
  end
end
```

#### Route cursor: `lux.route`

`nav.path` is the canonical request path. The router maintains its own offset
cursor on `lux.route` (also `current.route`) so routing doesn't mutate nav.

* `lux.route.path`     - remaining path after consumed segments
* `lux.route.root`     - first remaining segment
* `lux.route.child`    - second remaining segment
* `lux.route.consumed` - segments before the cursor
* `lux.route.with_scope(n) { ... }` - internal: push offset for the block

Inside `map 'admin' do ... end`, `lux.route.path` is the slice after `admin`
was consumed; `nav.path` is still the full `['admin', ...]`.

#### Class filters

* `config`      # pre boot app config
* `boot`        # after rack app boot (web only)
* `before`      # before any page load
* `routes`      # legacy single-block routes callback (top-level DSL is preferred)
* `after`       # after any page load

Errors anywhere in the routing/action pipeline are caught by
`Application#render_error` and dispatched to the active controller's `:error`
action. The action receives `@error` (the exception) and `@status` (resolved
HTTP status code) as instance variables. Override `error` on any controller
(or on a base class like `Api::BaseController`) to customise.
