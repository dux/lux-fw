# Roda-style routing support

## Goal

If `./app/roda.rb` exists, lux-fw uses it as the router instead of
`./app/routes.rb`. Roda becomes a routing DSL on top of Lux's existing
controller/response pipeline; ivar-passing to controllers, `rescue_from`,
and a reduced-scope `map` (named `lux_map`) all keep working.

If both files exist, `roda.rb` wins.

## Constraint: zero impact on existing apps

The vast majority of code lives in `Lux::Roda < ::Roda`, in
`lib/lux/roda.rb`. That file is only `require`d when the user actually opts
in (typically via `require 'lux/roda'` at the top of `app/roda.rb`). Apps
that never use Roda never load it and see zero behaviour change.

Net diff to existing Lux core:

* `Lux::Controller.dispatch` extraction (refactor, no behaviour change).
* ~5-line if-branch in `Lux::Application#resolve_routes` that is a no-op
  when no Roda app is registered.

Nothing else. No throw renames, no boot-detection plumbing in Lux (the
`Lux::Roda.inherited` hook self-registers).

## Response flow analysis (the gating question)

Walking through `Lux.call -> Application#render_base`:

```
:before callback
static-files check
resolve_routes  --catches :done-->  user's routing block sets lux.response.body
not_found unless body
lux.response.render self       <-- this is THE rack tuple producer
                                   (status, headers, etag, max_age, body -- all from lux.response)
```

Everything downstream of routing flows through `lux.response`. So as long as
Roda only *decides which controller to dispatch* and we route that dispatch
through `Lux::Controller.dispatch` (post-refactor), the response flow stays
single-source. Roda's own response object is ignored.

Concretely:

```
resolve_routes
  catch :done do
    user_roda_app.call(lux.request.env)
      route block runs
        r.on 'admin' do
          lux_map 'admin/dashboard#index'
            -> Lux::Controller.dispatch(...)
                 sets @ivars on controller, runs action, fills lux.response.body
            -> throw :done           # escapes Roda's block and resolve_routes' catch
        end
  end
lux.response.render self
```

The `:done` throw works because Roda only catches its own `:halt`. Roda's
return values are discarded. Lux's response, flash, etag, send_file, status --
all still authoritative.

**Verdict**: response flow is clean. The Roda app is reduced to a routing DSL;
the controller -> response pipeline is unchanged.

The only failure mode is a user writing `r.is('foo') { "hello" }` (returning a
string without calling `lux_map`). That gives a 404 because `lux.response.body`
never gets set. Document it as "always finish with `lux_map`" or, if it bites,
add a one-line Roda plugin later that promotes the return value into
`lux.response.body`. Not needed for v1.

## Build order

### 1. Refactor: extract `Lux::Controller.dispatch`

Per `doc/router-refactor.md:448`. Extract `Routes#call`'s
resolve+only/except+ivar-copy tail (`routes.rb:197-227`) into a class method:

```ruby
Lux::Controller.dispatch(target, ivars: {}, only: nil, except: nil)
```

`Routes#call` becomes a thin wrapper that resolves args and delegates. Ship
this as its own commit -- it is a strict win independent of Roda.

While extracting, add a `lux_map` instance method on `Lux::Application` that
is a thin shim around `Lux::Controller.dispatch(target, ivars:
instance_variables_hash)`. This lets the same handler body
(`lux_map 'main#error'`) be used inside `rescue_from`, regardless of whether
the app uses classic Lux routing or `Lux::Roda` -- because the
`rescue_from` block is `instance_exec`'d on the `Lux::Application` instance
(`application.rb:65`), not on the Roda app.

### 2. Lux::Roda subclass

New file: `lib/lux/roda.rb`, ~80 LOC. Required only on user opt-in.

```ruby
require 'roda'

class Lux::Roda < ::Roda
  # Self-register on subclassing so Lux core never needs boot-detection code.
  def self.inherited(subclass)
    super
    Lux.config[:roda_app] = subclass
  end

  # Class-level DSL: mirrors Lux.app rescue_from semantics.
  def self.rescue_from(&block)
    Lux::Application.rescue_from(&block)
  end

  # Inside Roda's route block: dispatch to a Lux controller.
  # Ivars set on the Roda routing instance (e.g. @user = ...) are copied
  # into the controller, same bridge as Lux::Application::Routes#call.
  #
  # Before dispatch we sync lux.nav.path from Roda's remaining_path so that
  # `nav.id`, `nav.last`, and the implicit-action default in
  # Lux::Controller.dispatch (last segment or :index) resolve against the
  # segments Roda has NOT yet consumed -- not the original full URL.
  def lux_map(target, ivars: nil)
    remaining = Lux.current.request.env['roda.remaining_path'] || request.remaining_path
    Lux.current.nav.path = remaining.sub(%r{^/}, '').split('/')
    Lux::Controller.dispatch(target, ivars: ivars || instance_variables_hash)
    request.halt   # short-circuit Roda's route tree; Lux's lux.response wins
  end

  private

  def instance_variables_hash
    instance_variables.each_with_object({}) { |v, h| h[v] = instance_variable_get(v) }
  end
end
```

### 3. Wire-in (the only Lux-core change beyond the refactor)

In `Lux::Application#resolve_routes` (`application.rb:150`), wrap the
existing routes-callback path with a guard:

```ruby
def resolve_routes
  catch :done do
    if roda_app = Lux.config[:roda_app]
      roda_app.call(lux.request.env)
    else
      run_callback :routes, lux.nav.path
    end
  end
end
```

No-op for any app that does not load `lux/roda`. `:before` / `:after`
callbacks defined via `Lux.app do ... end` still wrap the dispatch as today,
unchanged.

### 4. Gem dep

Add `gem 'roda'` to `lux-fw.gemspec` as a runtime dep. `require 'roda'`
happens inside `lib/lux/roda.rb`, which is only loaded when the user
explicitly `require`s it. Lux apps without Roda never load Roda.

## Example user code

```ruby
# app/roda.rb
require 'lux/roda'

class App < Lux::Roda
  rescue_from do |err|
    ExceptionDb.add err
    lux_map 'main#app_error'
  end

  route do |r|
    r.root { lux_map 'main#index' }

    r.on 'admin' do
      @user = User.current        # bridges to controller via instance_variables_hash
      r.is { lux_map 'admin#dashboard' }
      r.on('users') { lux_map 'admin/users' }
    end
  end
end
```

## What the user gives up vs current `routes.rb`

* `map text: 'main/root#text'` syntax -- Roda uses
  `r.is('text') { lux_map 'main/root#text' }`. Different shape, same result.
* `subdomain :name do` -- Roda has `r.host` or use a `before` block.
* `get? { ... }` predicates -- Roda has `r.get { ... }`.

Stylistic, not capability losses.

## Findings from codex review (resolved)

* **Nav not shifted before controller dispatch.** Roda consumes path
  segments via its own `remaining_path`; `lux.nav` is not touched. Without
  syncing, `lux_map 'admin/users'` from inside `r.on('admin')` resolved the
  implicit action against the wrong segment (`#admin` instead of `#index`).
  Fix: `lux_map` syncs `lux.nav.path = request.remaining_path...` before
  calling `Lux::Controller.dispatch`. See the adapter snippet in step 2.

* **`rescue_from` block had no `lux_map`.** The block is `instance_exec`'d
  on the `Lux::Application` instance via `define_method(:app_rescue_from)`
  (`application.rb:65`), so `lux_map` -- defined only on `Lux::Roda` --
  raised `NoMethodError`. Fix: step 1 adds `lux_map` as a shim on
  `Lux::Application` itself, so both classic and Roda apps share one
  handler body.

## Risks / open edges

* **Throw symbols**: Lux throws `:done`, Roda throws `:halt`. They live in
  separate code paths and never need to be unified. `lux_map` uses
  `request.halt` (Roda's native) to short-circuit the route tree.
* **Roda's session/response objects**: harmless -- they exist but we ignore
  them. Do not encourage `response.write` from inside Roda; tell users to use
  `lux_map` or fall through.
* **Reloading**: `Lux::Reloader.run` (`application.rb:25`) probably needs to
  invalidate the Roda app class on dev reload, or dispatching hits a stale
  class. Easy fix once it shows up.

## Effort

* Step 1 (refactor): ~1-2 hours, plus tests.
* Step 2 (adapter): ~1-2 hours.
* Step 3 (wire-in + boot detection): ~1 hour.
* Step 4 (gem + docs): ~30 min.
* Total: ~half-day plus iteration on edge cases.

Confidence the response flow stays clean: high.

## Reference points in current code

* `lib/lux/application/application.rb:21` -- `render_base`
* `lib/lux/application/application.rb:65` -- `self.rescue_from`
* `lib/lux/application/application.rb:150` -- `resolve_routes`
* `lib/lux/application/lib/routes.rb:152` -- `Routes#call` (dispatch tail at 197-227)
* `lib/lux/application/lib/routes.rb:228` -- `instance_variables_hash` ivar bridge
* `lib/lux/application/lux_adapter.rb:3` -- `Lux.app do ... end` entry
* `doc/router-refactor.md:448` -- prior proposal for `Controller.dispatch` extraction
