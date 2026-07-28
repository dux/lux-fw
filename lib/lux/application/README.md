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
    nav.map_path   # classify id segments; format from Lux.config.ref_format
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
    map 'reports', 'admin/reports#monthly'       # /admin/reports -> #monthly
  end

  map '/api'           => ApiApp                 # any Rack-callable class
  map '/admin/sys/jobs' => LuxJobWeb             # deep absolute path
  call '/api'          => ApiApp                 # unconditional (for rescue_from etc.)

  favicon '/favicon.svg'                         # serve at /favicon.ico + inject <head> links (web_common)
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
| `map 'foo#bar'`         | **none (unconditional)** | `FooController#bar` explicit |
| `map 'a', 'foo'`        | match `/a`   | `FooController`, resourceful |
| `map 'a', 'foo#bar'`    | match `/a`   | `FooController#bar` explicit |
| `map a: 'foo'`          | match `/a`   | `FooController`, resourceful |
| `map 'foo' do ... end`  | match `/foo` | enter scope, block at request time |
| `map '/abs/:var' => 'foo#bar'` | absolute path with capture | explicit |
| `map [:foo, :bar] => 'root'` | match either | `RootController` |
| `map 'a', 'foo', x: 1`  | match `/a`   | `FooController`, sets `@x = 1` |
| `call 'foo#bar'`        | none (unconditional) | explicit |
| `call -> { [200, {}, ['OK']] }` | none | return Rack tuple |

A lone `'controller#action'` string has no left-hand side to match against, so
`map 'foo#bar'` is exactly `call 'foo#bar'` - it runs on **every** request that
reaches it, including inside a `map 'admin' do` scope. To gate it on a segment,
give it one: `map 'foo', 'foo#bar'`.

## Halting

A dispatch that writes the response body throws `:done`. It is caught in one
place, `Application#resolve_routes`, so the first match ends routing: every
later statement in the block - and any remaining `routes do` callback - is
skipped outright. Guarding trailing statements with `unless response.body?` is
therefore unnecessary for anything after a `map` / `call` / `root`.

Code that writes the body *without* dispatching (a bare
`response.body 'ok' if nav.root == 'healthcheck'`, `response.send_file`,
`response.redirect_to`) does not throw, so it does still need a guard - or use
`redirect_to`, which throws `:done` for you.

## Conditions are evaluated per request, in the block

Everything inside `routes do ... end` (and every top-level routing statement)
runs per request. But a plain Ruby modifier on a **top-level** statement is
evaluated at class-eval time, when `Lux.current` is a `/mock` request:

```ruby
Lux.app do
  map about: 'static#about' if get?     # WRONG - `get?` runs once, at boot
  routes do
    map about: 'static#about' if get?   # right - evaluated per request
  end
  post? { map api: :api_router }        # right - the block runs per request
end
```

## Passing data to controllers

Instance variables set on the Application instance - in a `before` callback or
inside a `map ... do` scope block - are copied into the controller before the
action runs:

```ruby
map 'admin' do
  @org = Org[nav.ref]        # available as @org in Admin::* controllers
  map 'users', 'admin/users'
end
```

A trailing opts hash on `map` / `call` is the inline shorthand for the same:

```ruby
map 'users', 'admin/users', foo: :bar      # -> @foo = :bar
```

`:only` and `:except` are **reserved** in that hash - they gate the action
rather than becoming ivars (404 if the resolved action isn't allowed):

```ruby
map 'users', 'admin/users', only: [:index], foo: :bar
# gated to :index, and @foo = :bar
```

## Resourceful action resolution

The action is the **last segment that is not a classified id**, so it reads
straight off the tail of the URL. Id segments come from `nav.ref` (or
`nav.load_models`); the id itself is on `nav.ref`.

| URL                        | Action    | `nav.ref` |
|----------------------------|-----------|-----------|
| `/boards`                  | `:root`   | nil       |
| `/boards/edit`             | `:edit`   | nil       |
| `/boards/new`              | `:new`    | nil       |
| `/boards/123`              | `:show`   | "123"     |
| `/boards/123/edit`         | `:edit`   | "123"     |
| `/boards/users/123`        | `:users`  | "123"     |
| `/boards/users/123/edit`   | `:edit`   | "123"     |
| `/boards/foo/bar`          | `:bar`    | nil       |

Rules: empty remaining → `:root`; every segment is an id → `:show`; otherwise
the last non-id segment. One action serves both the collection and the member
form - branch on `nav.ref` when you need to.

Only methods the app defined on a `Lux::Controller` subclass are reachable this
way, so a URL can never dispatch into a framework method. Explicit
`'controller#action'` routing bypasses that check.

## Route cursor

`nav.path` is the canonical request path; `lux.route` is the per-request
cursor over it, and the single owner of path matching. `map` and controller
`filter` blocks advance the cursor without mutating nav, so a controller
mounted under a prefix never repeats that prefix.

| | |
|---|---|
| `lux.route.path`            | remaining path after consumed segments |
| `lux.route.root`            | first remaining segment |
| `lux.route.child`           | second remaining segment |
| `lux.route.consumed`        | segments before the cursor |
| `lux.route.match?(x)`       | does the cursor root match? String / Symbol / Regexp / Array |
| `lux.route.start_with?(*s)` | does the cursor start with these segments? |
| `lux.route.capture('/a/:b')`| absolute pattern match from the URL root; captures hash or nil |
| `lux.route.with_scope(n)`   | enter a scope for the block (used by `map` and `filter`) |

`-` and `_` are the same character to every one of those matchers, on both
sides, and the comparison is the only place it happens - `nav.path` keeps the
URL's original spelling, so slug lookups still see `my-post-title`.

```ruby
map 'cash-book'    # matches /cash-book and /cash_book
map :cash_book     # same
```

## Error handling

Errors anywhere in the routing/action pipeline are caught by
`render_error`. Resolution order:

1. `rescue_from { |err| ... }` if defined on the app (always wins)
2. Active controller's `:error` action (every controller inherits a default)
3. `Lux::Error.render` (last-resort framework page)

The `:error` action receives `@error` (exception) and `@status` (resolved
HTTP code) as ivars; the HTTP status also lives on `lux.response` (always an
integer, 200 unless set otherwise). By default it renders the single `error`
template at the layout root (e.g. `app/views/main/error.haml`) when present,
else a self-contained framework page - one template covers every status.
Override per controller for custom rendering.

## CLI

```bash
lux routes          # print the mounted route tree (shadow-executor)
lux routes -v       # add source location per entry
```

## See also

* [`../controller/README.md`](../controller/README.md) - actions
* [`../current/README.md`](../current/README.md) - `nav`, `route`, request state
* [`../response/README.md`](../response/README.md) - response builder
