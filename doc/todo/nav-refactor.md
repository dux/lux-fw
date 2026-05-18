# Nav Refactor

## Problem

`Lux::Application::Nav` is currently both:

* the request path object
* the router cursor
* the app-level canonical path after URL normalization

This makes routing hard to reason about. `nav.path` gets shifted, unshifted,
popped, and rewritten during request handling, so `nav.original` exists as an
escape hatch for code that still needs the incoming path.

The smell is not `nav.path` itself. The smell is using `nav.path` as a mutable
parser cursor.

## Current behavior

Framework internals:

* `lib/lux/application/lib/nav.rb`
  * stores `@path`
  * stores `@original = @path.dup`
  * exposes `shift` and `unshift`
  * tracks shifted segments with `@shifted`
  * supports `nav.path(:ref) { ... }` to rewrite ID-like path segments
* `lib/lux/application/lib/routes.rb`
  * block routes mutate nav:
    * `map 'admin' do ... end` shifts before yielding
    * restores with `unshift` in `ensure`
  * direct routes shift before calling:
    * `map 'admin', 'admin#call'`
  * `call 'main'` infers action from the shifted `nav.root`

This means the same request can have different `nav.path` values depending on
which route scope has already run.

## App usage patterns found

### Good canonicalization

This pattern is useful and should stay:

```ruby
nav.path.map! { |el| el.gsub('-', '_') }

nav.path :ref do |el|
  part = el.split('-').last
  Ulid.is?(part) ? part : nil
end
```

It turns URLs into app/template paths:

```text
/boards/my-board-01HX/edit
=> ["boards", :ref, "edit"]
```

and records IDs in `nav.id` / `nav.ids`.

### Router consumption

The framework consumes path segments with `nav.shift`.

Some apps also do this directly:

```ruby
nav.shift if nav.path[0, 2] == %w(admin dashboard)
```

or:

```ruby
Lux.current.session[:country] = nav.shift
```

This is where routing and app-level path state become tangled.

### Controller-local destructive parsing

Controllers sometimes mutate `nav.path` directly:

```ruby
@target = nav.path.shift
@id = nav.path.pop.string_id
tpl = auto_find_template nav.path.unshift(:admin)
```

These are local parsing concerns and should not modify global request
navigation.

### `nav.original` escape hatch

`nav.original` is used when code wants pre-shift state:

```ruby
Lux.current.nav.original.first
nav.original[1]
current.nav.original[1]
```

Common uses:

* scope links differently under `/admin`
* detect sudo/admin context
* parse task short URLs before `nav.path(:ref)` rewrites them
* call dynamic cells/templates after route shifting

Most of these should either use `nav.path` if canonical state is intended, or
`request.path` if raw input is intended.

## Proposed model

Separate the three concepts:

```text
request.path  - raw incoming URL path string
nav.path      - one canonical app path array
route.path    - router-local remaining path
```

`nav.path` should be the canonical request path and should not be used as a
routing cursor.

## Desired Nav API

Keep:

```ruby
nav.path
nav.path = [...]
nav.root
nav.child
nav.last
nav.id
nav.ids
nav.format
nav.locale
nav.domain
nav.subdomain
nav.pathname(...)
```

Keep and improve:

```ruby
nav.path(:ref) { |segment| ... }
```

Remove or deprecate:

```ruby
nav.original
nav.shift
nav.unshift
@shifted
```

Possible additions:

```ruby
nav.raw_path      # optional alias for request.path, if convenience is needed
nav.match(pattern)
nav.normalize! { |path| ... }
```

But avoid adding a second mutable path array. If raw data is needed, prefer
`request.path`.

## Route context

Routing should maintain its own scope/offset instead of mutating `nav.path`.

Conceptual API:

```ruby
route.path
route.root
route.child
route.consumed
```

Example:

```ruby
map 'dashboard' do
  route.path # remaining path after "dashboard"
  nav.path   # full canonical path
end
```

Internally `map` can push/pop an offset stack:

```ruby
with_route_scope(1) do
  yield
end
```

No global nav mutation is needed.

## Resourceful routes

The main reason for shifting appears to be resourceful routing: consume the
first segment so the next segment can become action or ID context.

Make this explicit instead.

Possible DSL:

```ruby
resource :boards, 'boards#call'
resources :boards, controller: 'boards'
```

Expected mapping:

```text
/boards              -> index
/boards/:ref         -> show
/boards/:ref/edit    -> edit
/boards/new          -> new
```

Since `nav.path(:ref)` already rewrites inline IDs, template paths remain clean:

```text
app/views/main/boards/root.haml
app/views/main/boards/ref/root.haml
app/views/main/boards/ref/edit.haml
```

This removes the need to shift `/boards` away just so `nav.root` can become the
action.

## Example before/after

Current:

```ruby
map 'admin', 'admin#call'

class AdminController
  def call
    tpl = auto_find_template nav.path.unshift(:admin)
    render tpl
  end
end
```

Target:

```ruby
map 'admin', 'admin#call'

class AdminController
  def call
    tpl = auto_find_template nav.path
    render tpl
  end
end
```

`nav.path` stays:

```ruby
["admin", "users", :ref, "edit"]
```

No shift. No unshift. No original.

## Migration plan

1. Keep `nav.path(:ref)` and document it as canonical URL normalization.
2. Add route context (`route.path`, `route.root`) while keeping old behavior.
3. Change route internals to use route offset instead of `nav.shift`.
4. Add resourceful route helper.
5. Replace app uses of `nav.path.shift`, `pop`, and `unshift` with local array
   copies or route/resource helpers.
6. Replace `nav.original`:
   * use `nav.path` for canonical path context
   * use `request.path` for raw URL parsing
   * use explicit variables for route-derived state
7. Deprecate `nav.shift`, `nav.unshift`, and `nav.original`.
8. Remove `@shifted` and delete old tests around shift/unshift/original.

## Notes from app scan

Direct mutation examples to revisit:

* `cms-lux/app/routes/routes.rb`
  * `nav.shift if nav.path[0, 2] == %w(admin dashboard)`
* OAuth controllers
  * `@target = nav.path.shift`
  * provider extraction via `nav.path.shift`
* Admin controllers
  * `auto_find_template nav.path.unshift(:admin)`
* Site/subdomain controllers
  * `nav.path.pop`
* `bolja-pomoc`
  * profile alias rewrites with `nav.path.unshift('terapeut')`
  * country/locale handling via `nav.shift`

`nav.original` examples to revisit:

* model path helpers using `Lux.current.nav.original.first`
* sudo/admin checks using `original[0] == 'admin'`
* dynamic cell calls using `current.nav.original[1]`
* short task URL parsing using `nav.original[1]`

## Opinion

The clean rule should be:

> `nav.path` is the canonical request path. Routing may inspect it, but not
> consume it.

Everything else follows from that. Router-local state belongs in `route`, raw
URL state belongs in `request.path`, and resourceful routing deserves an
explicit DSL instead of hidden `shift`/`unshift` behavior.
