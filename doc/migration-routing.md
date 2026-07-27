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

## Nav

### `nav.path(:ref) { }` is now `nav.ref { }`

`nav.path` did two unrelated jobs: read accessor with no block, in-place id
classifier with one. It is now a plain reader, and classification moved onto
`nav.ref` - the same shape `nav.locale { }` already had.

```ruby
# before, in a router before-filter
nav.path(:ref) { |el| Ref.is?(el) ? el : nil }

# after
nav.ref { |el| Ref.is?(el) ? el : nil }
```

The `:ref` argument is gone - it was never anything but `:ref`. Everything else
is unchanged: segments still become the `:ref` symbol, values still stack up in
`nav.refs` in path order, `nav.ref` still reads the first one, and re-running it
is still idempotent.

Two small behaviour fixes ride along:

* The block form used to return `refs.last` while `nav.ref` returns `refs[0]`.
  Both now return the first, so `nav.ref { ... }` and a later `nav.ref` agree.
* `nav.locale` with no block used to raise `LocalJumpError` on a locale-shaped
  path (it called `yield` with no `block_given?` guard). It now reads as a
  reader and returns nil.

App call sites to update: `racunovodstvo/app/routes.rb`, `bolja-pomoc/app/routes.rb`,
`sohospot.com-live/app/routes.rb`.

### `nav.ref=` removed

The setter's only caller was `action_route_match?`, deleted with the per-action
route registry. Nothing in the framework, the plugins or any app assigned to it.

### `nav.source_path` added

A frozen copy of the path taken at the end of `Nav#initialize` - lowercased,
extension and `key:value` segments already stripped, but before `nav.ref { }`,
`nav.locale { }` or any app rewrite touches it.

```ruby
GET /Boards/AB/edit.json

nav.source_path   # ['boards', 'ab', 'edit']   frozen, never changes
nav.path          # ['boards', :ref, 'edit']   after classification
request.path      # "/Boards/AB/edit.json"     raw Rack string
```

Use it when you need the path a second time and something in between may have
rewritten it. `plugins/pdf` was the worked example: it signs the request path
and re-verifies it on the follow-up render, so it used to snapshot the path into
`@pdf_path` in its `routes.rb` and thread that ivar into the controller. Both are
gone; the controller builds `'/' + nav.source_path.join('/')` on demand.

If you carried the same workaround (izlazni's `GuestController#pdf_view` re-splits
`request.path` and re-normalises it by hand), `nav.source_path` replaces it:

```ruby
# before
parts    = request.path.sub(%r{^/pdf/}, '').split('/')
kind     = parts[0]&.tr('-', '_')
ref      = parts[1]

# after
kind, ref, doc_type, slip_ref = nav.source_path.drop(1)
```
