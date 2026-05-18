# Nav / Route Refactor - Execution Plan

Derived from `doc/todo/nav-refactor.md`. Decisions made:

* Hard break - no deprecation shims for `nav.shift` / `nav.unshift` / `nav.original`.
* `nav[index]` and `nav.pathname` re-anchor to `nav.path` (canonical, post `:ref`).
* `nav.locale` keeps its current path-shift behavior (treated as canonicalization, same family as format stripping).
* Full doc scope: route object + `resource` / `resources` DSL.

## Step 1 - Add `Lux::Application::Route`

New file `lib/lux/application/lib/route.rb`:

```ruby
class Route
  def initialize(nav)
    @nav = nav
    @offsets = [0]
  end

  def path;     @nav.path[@offsets.last..] || []; end
  def root;     path.first; end
  def child;    path[1]; end
  def consumed; @nav.path[0, @offsets.last]; end

  def with_scope(n)
    @offsets.push(@offsets.last + n)
    yield
  ensure
    @offsets.pop
  end
end
```

Expose lazily via `Lux::Current` as `lux.route` / `current.route`.

## Step 2 - Rewire `routes.rb` to use `lux.route`

In `lib/lux/application/lib/routes.rb`:

* `map 'admin' do ... end` block branch: replace
  `lux.nav.shift` + `ensure lux.nav.unshift` with
  `lux.route.with_scope(1) { yield lux.route.root }`.
* `map 'admin', 'admin#call'` (String branch): wrap `call route_object` in `with_scope(1)`. `catch :done` stays inside the scope.
* `map [:foo, :bar] => 'root'`: wrap each match with `with_scope(1)`.
* Hash route fallthrough: wrap `call(klass, ...)` with `with_scope(1)`.
* Action inference:
  * `action = lux.nav.root.or(:index)` -> `lux.route.root.or(:index)`.
  * `action ||= lux.nav.path.last || :index` -> `lux.route.path.last || :index`.

## Step 3 - Strip Nav of shift/unshift/original

In `lib/lux/application/lib/nav.rb`:

* Remove `attr_reader :original`.
* Remove `@original`, `@shifted` ivars.
* Remove `shift`, `unshift` methods.
* Re-anchor `nav[]` and `nav.pathname` to `@path`. New `pathname`:

```ruby
def pathname(ends: nil, has: nil)
  pn = '/' + @path.map(&:to_s).join('/')
  return pn.include?("/#{has}") if has
  return pn.end_with?("/#{ends}") if ends
  pn
end
```

Leave: `set_format` empty-first-segment shift (init-only), `locale` shift.

## Step 4 - `resource` / `resources` DSL

```ruby
def resources(name, target)
  return unless route_match?(name)

  lux.route.with_scope(1) do
    remaining = lux.route.path
    action =
      if remaining.empty?              then :index
      elsif remaining[0] == 'new'      then :new
      elsif remaining[0] == :ref       then (remaining[1] || :show).to_sym
      else                                  remaining[0].to_sym
      end
    call target, action
  end
end

def resource(name, target)
  return unless route_match?(name)
  lux.route.with_scope(1) do
    action = lux.route.root&.to_sym || :show
    call target, action
  end
end
```

Contract: `nav.path(:ref) {}` runs before routing.

## Step 5 - Tests

* `spec/lux_tests/nav_spec.rb`:
  * Drop `#shift / #unshift` block.
  * Drop `#original` block.
  * Add `nav[]` with `:ref` after `nav.path(:ref) {}` rewrites.
* New `spec/lux_tests/route_spec.rb`: `with_scope`, `path`, `root`, `consumed`.
* Extend routing spec (or add `resources_spec.rb`): `/boards`, `/boards/new`, `/boards/:ref`, `/boards/:ref/edit`.

## Step 6 - Docs

Update `AGENTS.md`:

* Remove `nav.shift / nav.unshift` line.
* Note `nav[]` / `nav.pathname` now reflect canonical (post-`:ref`) path.
* Add `Lux::Application::Route` section.
* Add `resource` / `resources` to routing patterns.

## Out of scope

* Downstream app migrations (cms-lux, bolja-pomoc, ...).
* Locale extraction redesign.
* Nested resources.
