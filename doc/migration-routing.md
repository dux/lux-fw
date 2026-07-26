# Routing cleanup - what app authors need to change

The router lost the parts no app was using and gained one cursor instead of
three. Most apps need no changes at all; this lists the ones that do, in
descending order of how likely you are to hit them.

Canonical docs: [`../lib/lux/application/README.md`](../lib/lux/application/README.md)
and [`../lib/lux/controller/README.md`](../lib/lux/controller/README.md).

## Removed

### `route '/path'` above a `def`

Per-action URL annotations, the global `Lux::Controller::ACTION_ROUTES`
registry, and the pre-routes dispatch pass are gone. Declare the URL in the
router instead:

```ruby
# before - in the controller
route '/u/:slug'
def by_slug; end

# after - in app/routes.rb
map '/u/:slug' => 'users#by_slug'
```

Captures land in `lux.params` (they always did - the old doc claiming
`nav.params` was wrong; there is no such method).

### `ref do ... end` in a controller

The `_ref` action-name suffix is gone, so the macro that produced those names
went with it. One action now serves both the collection and the member URL -
branch on `nav.ref`:

```ruby
# before
def edit; end
ref do
  def edit                     # /boards/123/edit -> :edit_ref
    @board = Board.find(nav.ref)
  end
end

# after
def edit                       # /boards/edit AND /boards/123/edit -> :edit
  @board = Board.find(nav.ref) if nav.ref
end
```

Template lookup follows: there is no `show_ref.haml` -> `show.haml` fallback
because there is no `show_ref` action.

**`Lux::Api`'s `ref do` is a different macro on a different class and is
unchanged.** Model API files keep working as-is.

### Undefined helper calls at the top level of `Lux.app do ... end`

`Application.method_missing` no longer swallows unknown class-level calls into
the route callback list, and `respond_to_missing?` no longer answers `true` for
everything. A typo is now a `NoMethodError` at load time instead of at request
time. Helper calls belong inside `routes do ... end`, which is where every app
already puts them:

```ruby
Lux.app do
  routes do
    general_rules        # fine - runs per request
  end

  def general_rules
    ...
  end
end
```

The `map` / `root` / `match` / `subdomain` / `get?` / `plugin_route` /
`favicon` top-level forms still work.

### `Lux::Application::Shared`

Deleted - it duplicated `Lux::Lifecycle`. Replace `extend
Lux::Application::Shared` with `extend Lux::Lifecycle`; `redirect_to` moved
onto `Lifecycle` so nothing is lost.

## Changed

### Resourceful action resolution

The action is now the **last segment that is not a `:ref`**. Previously the
first segment was skipped whenever two or more remained, so a sub-resource name
appeared or vanished depending on whether an id followed it.

| URL                       | before      | after    |
|---------------------------|-------------|----------|
| `/boards/123`             | `:show_ref` | `:show`  |
| `/boards/123/edit`        | `:edit_ref` | `:edit`  |
| `/boards/users/123`       | `:show_ref` | `:users` |
| `/boards/users/123/edit`  | `:edit_ref` | `:edit`  |
| `/boards/foo/bar`         | `:foo`      | `:bar`   |

Only affects bare `map 'controller'` (no target) dispatch.

### Controller `filter` follows the route cursor

`filter :seg do` used to walk `nav.path` from index 0 with its own depth
counter, ignoring any `map` scope the controller was reached through. It now
reads `lux.route`, so a prefix-mounted controller must **not** repeat the
prefix:

```ruby
map 'dev', 'dev#auto'          # router consumes 'dev'

class DevController < FrontendController
  layout :dev

  # before
  before { nav.path.shift }    # delete this
  filter :dev do
    filter :settings do ... end
  end

  # after
  filter :settings do ... end
end
```

If you had a `before { nav.path.shift }` to compensate, remove it - it now
shifts one segment too many. Controllers mounted at the root (`call 'main#auto'`)
are unaffected: with no scope entered, `lux.route.path == nav.path`.

`auto_render` and `auto_find_template` follow the same cursor. A controller
that called `auto_find_template nav.path` by hand should call `auto_render`,
which prefixes the view dir for you and raises a proper 404 on a miss.

### `:done` is caught in exactly one place

A dispatch that writes the response body throws `:done`, caught only in
`Application#resolve_routes`. Previously `map` caught it locally and the rest
of the route block kept running as no-ops, so work after a match (extra DB
queries, model loading) still executed. Now the first match ends routing.

Practical effect: guards like `unless response.body?` around statements that
follow a `map` / `call` / `root` are no longer needed. Guards after code that
writes the body *without* dispatching (`response.body 'ok' if healthcheck`,
`response.send_file`) are still needed - those do not throw.

### `root?` in the router reads the cursor

`Routes#root?` used to delegate to `nav.root?` (absolute). It now matches the
cursor, so inside `map 'admin' do` it tests the segment after `/admin` - the
same frame of reference as `root` and `map`. `nav.root?` is unchanged if you
want the absolute answer.

### `render_to_string` no longer writes the response

It now does what its name and docs always claimed: returns the markup without
touching `lux.response`. If you relied on the side effect, call `render`.

## Optional cleanups

### Drop `set_nav_ref`

```ruby
def set_nav_ref
  nav.path.map! { |el| el.gsub('-', '_') }
end
```

The router now treats `-` and `_` as the same character on both sides of every
comparison (`map`, `filter`, `match`, resourceful dispatch), and template names
are underscored at lookup time. This helper is redundant.

Removing it also un-mangles `nav.path`, which is the point: a slug URL keeps
its dashes, so `Post[slug: nav.path[1]]` works. Check any code that reads
`nav.path` for a slug before deleting the helper - that mismatch is what forced
hand re-parsing of `request.path` in a few apps.

### Use the block form for path-scoped guards

```ruby
# before - repeated in most app routers
def admin_routes
  if nav.root == 'admin'
    raise Lux.error.not_found('Not an admin') unless user&.can&.admin?
    map 'admin', 'admin#call'
  end
end

# after - the cursor advances, so nested routes and controller filters compose
map 'admin' do
  raise Lux.error.not_found('Not an admin') unless user&.can&.admin?
  plugin_routes
  call 'admin#call'
end
```
