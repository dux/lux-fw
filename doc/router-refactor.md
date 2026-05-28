> STATUS: design proposal - NOT implemented. Describes a possible future router, not current behavior.

# Router Refactor - Architecture Reference

Snapshot of how the request pipeline currently works, written as a baseline before any router refactor. File/line refs are against `master` at the time of writing.

> Note: the "Architecture Reference" section below documents real current code.
> The "Refactor plan" section is aspirational and was NOT carried out - in
> particular `rescue_from` still exists and was NOT removed.

## Request flow at a glance

```
Rack
  - Lux.call(env)                                    lib/lux/lux.rb:15
  - Lux::Application.new(env)                        lib/lux/application/application.rb:25
      - Lux::Current.new(env)                        lib/lux/current/current.rb:11
          - Thread.current[:lux] = self
            (request, response, nav, session, params, var)
  - app.render_base                                  lib/lux/application/application.rb:30
      - run_callback :before
      - static files (if Lux.config.serve_static_files)
      - resolve_routes                               lib/lux/application/application.rb:143
          - run_callback :routes
          - user-defined Lux.app { ... } block
              - map / root / get? / post? / match    lib/lux/application/lib/routes.rb
                  - Routes#call -> Controller#action routes.rb:152, controller.rb:67
      - 404 fallback if no body
      - lux.response.render(self)                    lib/lux/response/response.rb:214
        returns [status, headers, [body]]
```

The full hot path is only four calls deep: `Lux.call` * `Application#render_base` * `Routes#call` * `Controller#action`. There is no internal middleware stack between them.

## 1. Entry point

`lib/lux/lux.rb:15`

```ruby
def call env = nil
  Timeout::timeout Lux::Config.app_timeout do
    app = Lux::Application.new env
    app.render_base || raise('No RACK response given')
  end
rescue => err
  # 500 fallthrough
end
```

`config.ru` integration (`lib/lux/lux.rb:163`) hooks `Rack::Builder`. A `Lux do ... end` (or bare `Lux()`) call inside the rackup file class-evals the block into `Lux::Application` (same DSL as `Lux.app do ... end`), registers the framework as the Rack app, and prints `Lux::Config.start_info`.

Thread-local context is exposed two ways:

* `Lux.current` - module accessor
* `Object#lux` - global shortcut available in every object, reading `Thread.current[:lux]`

## 2. Application

`lib/lux/application/application.rb`

* Includes `ClassCallbacks` and the `Routes` module.
* Callbacks: `:before`, `:routes`, `:after` (lines 11-13).
* `initialize(env)` only constructs `Lux::Current`. The Application instance itself is a thin shell - all state lives on `Lux.current`.
* `render_base` orchestrates the lifecycle:
  1. `run_callback :before, lux.nav.path`
  2. Short-circuit `OPTIONS` with a 204
  3. Optional static-file serving via `Lux::Response::File.deliver_from_current`
  4. `resolve_routes` (only if no body yet)
  5. `Lux.error.not_found` if still no body
  6. `lux.response.render(self)` to emit the Rack tuple
* Wrapped in `rescue StandardError` that calls `app_rescue_from(err)` if the app defines one, otherwise the default `rescue_from`.

## 3. Current - request state container

`lib/lux/current/current.rb:11`

```ruby
def initialize env = nil, opts = {}
  @env     = env || '/mock'
  @env     = ::Rack::MockRequest.env_for(env) if env.is_a?(String)
  @request = ::Rack::Request.new @env

  Thread.current[:lux] = self

  @files_in_use = Set.new
  @response     = Lux::Response.new
  @session      = Lux::Current::Session.new @request
  @nav          = Lux::Application::Nav.new @request
  @var          = { cache: {} }.to_hwia
end
```

Why this matters: the framework does not pass request state through the call chain. Every layer (Application, Routes, Controller, helpers, views) reads from the same `Lux.current` instance. This is why a controller can `throw :done` and have routing know to stop - both sides check `lux.response.body?`.

Exposed attributes used by routing/controllers:

* `@request` - `Rack::Request`
* `@response` - `Lux::Response` (status, headers, body, redirects, flash)
* `@nav` - `Lux::Application::Nav` (path stack, domain, format)
* `@session`, `@params`, `@var`

## 4. Nav - path as a stack

`lib/lux/application/lib/nav.rb:8`

`@path = request.path.split('/').slice(1, 100) || []`

Key methods:

* `root` - first remaining segment
* `shift` - remove first segment, push to `@shifted`
* `unshift(name = nil)` - put name back, or pop from `@shifted`

Nested `map` blocks consume segments by `shift` on entry and `unshift` on exit. This is what lets routes compose without building regexes:

```ruby
map 'admin' do
  # nav.path now starts one segment deeper
  map 'users' => 'admin/users'
end
# nav.path restored on exit
```

`nav.path(:ref) { |el| ... }` lets a route extract IDs from path segments and rewrite them to a marker.

## 5. Router (Routes module)

`lib/lux/application/lib/routes.rb` - mixed into `Application`, so `map`, `root`, `get?`, etc. are instance methods on the app object.

### HTTP predicates (lines 11-27)

```ruby
%w{get head post delete put patch}.each do |m|
  define_method('%s?' % m) do |*args, &block|
    cm = lux.request.request_method
    cm = 'GET' if cm == 'HEAD'
    return unless cm == m.upcase
    if block          then block.call
    elsif args.first  then map *args
    else                   true
    end
  end
end
```

Three usage modes per predicate: bare check (`get?`), with a target (`get? 'main/root#index'`), or with a block.

### Path matchers

* `root target` (line 34) - matches when `nav.root` is empty.
* `match base, target` (line 40) - splits `base` on `/`, walks segments, copies `:placeholders` into `lux.params`, otherwise requires literal match.

### `map` (line 74) - main dispatcher

Accepts a wide surface:

* `map api: 'api'` - hash form
* `map [api: 'main/root']`
* `map [:foo, :bar] => 'root'` - multiple bases
* `map '/skills/:skill' => 'main/skills#show'` - regex-style with placeholders
* `map 'admin' do ... end` - nested block, with `nav.shift`/`unshift` bracketing the yield

Returns immediately if `lux.response.body?` - once a body is set, every route call no-ops.

### `call` (line 152) - resolve and invoke

Normalises the target into `(controller_class, action, opts)`:

* String `'main/orgs'` -> `Main::OrgsController`, action defaults to `nav.path.last || :index`
* String `'main/orgs#show'` -> class + action `:show`
* Symbol -> `send(symbol)` on the app (sub-router method)
* Proc -> call and treat result as body
* Array -> direct Rack tuple `[200, {}, 'ok']`
* Class with `.call` -> mounted as a Rack app via `lux.response.rack`
* Class with `.action` -> `klass.new.action(action_sym, ivars: instance_variables_hash)`

Other behaviour:

* `CONTROLLER_CLASS_CACHE` (line 6) memoises string -> class lookups; after warmup, route resolution is a hash hit, not `constantize`.
* `opts[:only]` / `opts[:except]` enforced before invocation; mismatch raises `Lux.error.not_found`.
* `throw :done if lux.response.body?` after invocation, unwinding nested `map` blocks.

## 6. Controller

`lib/lux/controller/controller.rb`

* Plain class (no parent). Includes `ClassCallbacks`.
* Class attrs: `cattr :layout`, `cattr :template_root` (default `./app/views`).
* Callbacks: `:before`, `:before_action`, `:before_render`, `:after` (lines 14-17).

### `action(method_name, ivars:)` (line 67)

```ruby
def action method_name, args: [], ivars: {}
  ivars.each { |k, v| instance_variable_set(k, v) }
  @lux.action = method_name.to_sym

  run_callback :before, @lux.action

  catch :done do
    unless lux.response.body?
      run_callback :before_action, @lux.action
      if respond_to?(method_name)
        send method_name, *args
      else
        action_missing method_name
      end
      render
    end
  end

  run_callback :after, @lux.action
end
```

Lifecycle: copy ivars from Application * `:before` * `:before_action` * action method (or `action_missing` for autoroutes) * `render` * `:after`. The whole body is wrapped in `catch(:done)` so any layer can short-circuit by throwing.

### `render` (line 159)

Three modes:

1. **Static** - `render text:`, `render json:`, `render html:` * `render_static` (line 200) sets body and content type directly.
2. **Template** - `render :index` or `render 'main/root/index'` * `render_template` (line 230) builds `template_root/<helper>/<action>` (or absolute if path contains `/`), runs `Lux::Template.render(helper_ctx, opts)`, wraps in layout if requested.
3. **Cached** - `render_cache :key` (line 212) etag-aware page cache, skipped when flash messages are present.

All three end at `lux.response.body data`.

### Helper context (line 259)

```ruby
HELPERS ||= {}
def helper helper
  HELPERS[helper] ||= Class.new Object do
    include Lux::Template::Helper
    include HtmlHelper
    include ApplicationHelper
    include "#{helper.to_s.classify}Helper".constantize if helper.present?
  end
  ctx = HELPERS[helper].new
  for k, v in instance_variables_hash
    ctx.instance_variable_set("@#{k.to_s.sub('@','')}", v)
  end
  ctx
end
```

Anonymous helper class per layout name, ivars copied from controller. Cached per process.

### action_missing (line 320)

If `Lux.config.use_autoroutes` is on and a template file exists for the missing method, defines the action on the fly so subsequent hits skip the lookup.

### Delegations to `lux` (lines 117-123)

```ruby
define_method(:current)  { Lux.current }
define_method(:request)  { lux.request }
define_method(:response) { lux.response }
define_method(:params)   { lux.params }
define_method(:nav)      { lux.nav }
define_method(:session)  { lux.session }
define_method(:user)     { lux.user }
```

The controller carries no request state of its own beyond `@lux` (an internal `IVARS` struct holding `template_suffix`, `action`, `layout`).

## 7. Response

`lib/lux/response/response.rb`

* `status(num)` (line 72), `body(data, opts)` (line 94), `header(k, v)` (line 26)
* `redirect_to(where, opts)` (line 146)
* `send_file(file, opts)` (line 140)
* `flash` (line 135)
* `render(app = nil)` (line 214) - finalises and returns the Rack tuple `[@status, @headers.to_h, [@body]]`. If passed the Application, runs its `:after` callback before returning. HEAD requests get an empty body.

## 8. Cross-cutting design choices

* **State via thread-local**, not parameter passing. `Lux.current` plus `Object#lux` mean every layer sees the same context without explicit wiring.
* **Path as a mutable stack** in `Nav`. Nested routing composes by `shift`/`unshift` rather than regex assembly.
* **`throw :done` as the universal early-exit**. The router checks `lux.response.body?` at the top of `map`/`call`; the controller's `action` runs inside `catch(:done)`. Either side can stop the pipeline by setting a body.
* **Controller class cache** (`CONTROLLER_CLASS_CACHE`) keeps route dispatch at hash-lookup cost after warmup.
* **Single-pass, no internal middleware**. Lux is itself the Rack app. There is one entry, one exit, four calls between them.

## Things to be aware of when refactoring the router

These are observations, not prescriptions - flagging them so a refactor doesn't accidentally break invariants the current code relies on.

* **`map`/`call` overloading.** `Routes#call` accepts at least six target shapes (string, string-with-#action, symbol, proc, array tuple, class). Splitting `call` into typed dispatchers would help, but the public surface (`map api: '...'`, `map [...] => '...'`, `map 'x' do ... end`) is exposed to user route files and must stay stable.
* **Nav mutation is load-bearing.** The `shift`/`unshift` pairing in `map` (routes.rb around line 90) is what makes nested routes work. Any refactor that switches to immutable path slices needs to re-thread the "current depth" through every matcher and predicate.
* **`lux.response.body?` is the single source of truth** for "are we done." It's checked in `render_base`, `map`, `call`, and `Controller#action`. A refactor that introduces an explicit return value chain still needs to honour this, or callbacks will run twice.
* **`throw :done`** is caught only inside `Controller#action`. If routing-level code starts throwing it, add a matching `catch` in the router.
* **`CONTROLLER_CLASS_CACHE`** is a process-wide hash. In dev with code reloading, stale class references will linger - any refactor that keeps the cache must invalidate on reload.
* **`instance_variables_hash`** is passed from Application to Controller in `Routes#call` (routes.rb:222) and copied in `Controller#action` (line 73). This is how ivars set in the routes block (e.g. `@current_user = ...`) reach the controller. Removing this bridge would silently break any app relying on it.
* **`HELPERS` constant** in `Controller` (line 259) memoises anonymous helper classes by layout name. Tests that define ad-hoc helpers per example will leak entries.
* **Callbacks fire on the Application instance**, not the controller, for `:before`/`:routes`/`:after`. Controller has its own `:before`/`:before_action`/`:before_render`/`:after`. Keep them distinct; conflating them would change order-of-execution semantics.

## File index

| Concern              | Path                                                  |
| -------------------- | ----------------------------------------------------- |
| Rack entry           | `lib/lux/lux.rb`                                      |
| Application class    | `lib/lux/application/application.rb`                  |
| Routes module        | `lib/lux/application/lib/routes.rb`                   |
| Nav (path stack)     | `lib/lux/application/lib/nav.rb`                      |
| Current (req state)  | `lib/lux/current/current.rb`                          |
| Controller           | `lib/lux/controller/controller.rb`                    |
| Response             | `lib/lux/response/response.rb`                        |

---

# Refactor plan

Two related but separable changes. Both can ship together or in order; together they are coherent.

* **Part A — Unify** the duplicated machinery between `Application` and `Controller` via a shared mixin.
* **Part B — Simplify error handling** by deleting the `rescue_from` macro and routing errors through an ordinary controller action.

## Goals

* One `render`, one set of `lux.*` delegators, one callback mechanism — not two near-copies.
* Errors are just another route target. The framework dispatches to a controller action; the controller renders normally.
* `Lux::Application` keeps a narrow role: drive the Rack lifecycle, call the router, catch errors, dispatch to an error action. If *that* fails, give up to a low-level Rack response.
* Effectively zero changes for user app code (one optional migration for users of `rescue_from`).

## Concretely duplicated today

* **Delegators to `lux.*`** — identical 7-line block at `application.rb:17-23` and `controller.rb:117-123`.
* **Static `render`.** `application.rb:84-100` only handles `text:`/`html:`/`json:`/`xml:`/`javascript:`. `controller.rb:200-209` (`render_static`) is the same five-type switch, reachable through the full `Controller#render`.
* **Callback declarations.** Both classes `include ClassCallbacks` and define `:before`/`:after`. Different middle slots (`:routes` on Application; `:before_action`/`:before_render` on Controller), but the boilerplate is repeated.
* **Action dispatch.** `Routes#call` (`routes.rb:152-228`) and `Controller#controller_action_call` (`controller.rb:305-318`) are two ways to spell "given `'main/orgs#show'`, look up the class and invoke `.action(:show)` with ivars."

## What stays distinct

* **`render_base`** (Rack lifecycle), **`render_page`**, **`mount`**, **`favicon`**, **`resolve_routes`** — all Application-only.
* **Routes DSL** (`map`, `get?`, `match`, `root`, `subdomain`, `call`, `route_match?`) — mixed into Application only. Controllers do not route to other controllers; that is the router's job.
* **Controller-only mechanics** — `action_missing`, `helper`, `render_template`, `render_cached`, `respond_to`, `layout`, `cache`, `etag`. Stay on Controller.

## Proposed shape

```
Lux::Lifecycle  (mixin: callbacks, lux.* delegators, render, IVARS/RENDER_OPTS structs)
   |
   ├─ included in Lux::Controller   (action dispatch + helpers + templates)
   └─ included in Lux::Application  (Routes module + Rack lifecycle + error orchestration)
```

Mixin (sibling) chosen over inheritance (`Application < Controller`) for one reason: the Application is **not** a Controller. Its narrow role is router-driver + error orchestrator. Making it a Controller subclass would silently inherit `helper`, `render_template`, `action_missing`, `respond_to` etc. — methods that have no business being callable on the request-lifecycle object.

`Lux::Lifecycle` owns:

* `:before` and `:after` callback definitions (via `ClassCallbacks`).
* The 7 `lux.*` delegators (`current`, `request`, `response`, `params`, `nav`, `session`, `user`).
* The full `render(name = nil, opts = {})` method — the same one currently in Controller. Application's stripped-down version is deleted; the inherited full `render` handles `text:`/`html:`/etc. as a subset and ignores template/layout opts when called on an Application instance (or, equivalently, that path is never exercised on Application).
* `IVARS` and `RENDER_OPTS` structs.

`Lux::Controller` adds: `:before_action`, `:before_render` callbacks, `action`/`action_missing`, `render_template`, `render_cached`, `helper`, `respond_to`, `layout`, `cache`, `etag`, `redirect_to`, `flash`, `send_file`, `render_to_string`, `render_javascript`. **Plus a default `error` action** (see Part B).

`Lux::Application` adds: `include Routes`, `:routes` callback, `render_base`, `render_page`, `resolve_routes`, `mount`, `favicon`, `render_error`.

## Part B — Error handling

### Today

* `Lux.app do rescue_from { |err| ... } end` registers `app_rescue_from`.
* `render_base`'s `rescue StandardError` calls it, or falls back to `Lux::Error.render`.
* If the user's `rescue_from` block itself raises, `Lux.call`'s outer `rescue` returns a 500.

### After

Drop the `rescue_from` macro entirely. Application catches and dispatches to a controller's `error` action — the same mechanism as any other route target.

```ruby
# In Application
def render_base
  # ... lifecycle ...
  resolve_routes unless lux.response.body?
  Lux.error.not_found unless lux.response.body?
  lux.response.render self
rescue StandardError => err
  render_error err
end

private

def render_error err
  Lux.logger.error Lux::Error.format(err)
  ivars = { error: err, status: Lux::Error.status_for(err) }
  klass = lux.var[:active_controller] || Lux::Controller
  lux.response.reset!  # clear partial body if any
  klass.action(:error, ivars: ivars)
  lux.response.render
end
```

### Resolution rule for which controller's `error` runs

* `Routes#call` records the controller class right before dispatch: `lux.var[:active_controller] = klass`.
* On error, `render_error` invokes `.action(:error, ...)` on that class.
* If no controller was active (error happened in a router-level `before`, or before any match), fall through to `Lux::Controller` itself.

There is no `Lux.config.error_controller` knob and no `MainController`-as-fallback branch. The fallback is built into the inheritance chain: every controller inherits `Lux::Controller#error`, so calling `.action(:error, ...)` on any class always works.

### Default `error` on `Lux::Controller`

Ships with the framework. Verbose in dev, plain in prod, format-aware:

```ruby
def error
  @error  ||= lux.var[:error]
  @status ||= lux.var[:error_status] || 500
  lux.response.status @status

  if lux.nav.format == :json || request.content_type.to_s.include?('json')
    render json: { error: @error.message, status: @status }
  elsif Lux.env.dev?
    render html: Lux::Error.format(@error, message: true, gems: false, backtrace: true)
  else
    render html: "<h1>#{@status} #{Rack::Utils::HTTP_STATUS_CODES[@status]}</h1>"
  end
end
```

User overrides anywhere they want richer behaviour:

```ruby
class MainController < Lux::Controller
  def error
    render @status == 404 ? :error_404 : :error_500
  end
end

class Api::BaseController < Lux::Controller
  def error
    render json: { error: @error.message, status: @status }
  end
end
```

API/HTML/admin diverge naturally through ordinary inheritance — no framework branching.

### User-facing migration

* Apps with no `rescue_from`: **zero changes**. They get a nicer default error page in dev (current default chrome is `Lux::Error.render`; new default is the same content rendered through the controller pipeline).
* Apps with `rescue_from { |err| MainController.render_template(:error_500, self) }`: replace with `def error; render :error_500; end` on `MainController`. Net change: ~1 file moved, ~3 lines.
* For one release, keep a deprecated `rescue_from` shim that synthesises an `error` method on a one-off controller — adds ~15 lines of compat that get deleted in v-next. Recommended unless we are willing to make the cutover hard.

## Step-by-step migration

Each step is independently shippable; run specs between each.

1. **Extract `Lux::Lifecycle` mixin.** New file `lib/lux/lifecycle.rb` (or co-located with Controller). Move the 7 delegators in. Move the `:before`/`:after` `define_callback` declarations in. Include from both `Controller` and `Application`. Delete the duplicate delegator block from `application.rb:17-23`. Pure refactor.
2. **Move full `render` into `Lifecycle`.** Move `Controller#render` and its helpers (`normalize_render_opts`, `render_static`) into `Lifecycle`. Delete `Application`'s mini-`render` at `application.rb:84-100`. Verify `Lux.app do ... render text: 'ok'; end` still works (it should — the inherited `render` is a strict superset).
3. **Extract shared dispatch.** Pull `Routes#call`'s class-resolution + only/except + ivar-copy block (roughly `routes.rb:197-227`) into a class method `Lux::Controller.dispatch(target, ivars: {}, only: nil, except: nil)`. Have both `Routes#call` and `Controller#controller_action_call` call it. (Or delete `controller_action_call` if grep shows it is internal-only.)
4. **Add `lux.var[:active_controller] = klass`** in `Routes#call` right before the `klass.action(...)` call. No behaviour change yet — just instrumentation.
5. **Add default `Lux::Controller#error`** action (sketch above). No callers yet, so no behaviour change.
6. **Switch `render_base` rescue** to `render_error err`. Delete the `rescue_from` macro and `app_rescue_from` indirection at `application.rb:64-79`. (Optionally add the deprecation shim.) Update the demo app and any spec that exercises the old path.
7. **Tidy.** Confirm `Lux::Error.render` is now only reached from `Lux.call`'s outer rescue (the absolute-bottom fallback). Confirm the demo app renders nice errors in dev.

## Invariants that must survive

* **Ivars from router flow into controller action.** `instance_variables_hash` at `routes.rb:222-224` → `Controller#action`'s `ivars:` copy at `controller.rb:72`. The shared `Controller.dispatch` from step 3 must keep doing this. The router instance has its own ivars and they continue flowing through.
* **`throw :done` short-circuits.** Both `Routes#call` and `Controller#action` check `lux.response.body?`. Keep both checks.
* **`CONTROLLER_CLASS_CACHE`** stays on the `Routes` module (process-wide, not per-subclass).
* **Callback firing scopes.** Application's `:before`/`:after` fire once per request on the Application instance. Controller's `:before`/`:before_action`/`:before_render`/`:after` fire per action on the controller instance. The mixin shares the *mechanism*, not the firing site.
* **Two-tier rescue.** `Application#render_base` catches once and dispatches to `error`. `Lux.call` catches once more as the absolute floor. No third tier.
* **`Lux.app do ... end` DSL** is unchanged: `before`, `after`, `map`, `root`, `match`, `get?`, `post?`, `subdomain`, `mount`, `favicon`. The only macro that disappears is `rescue_from`.

## What gets deleted

* `application.rb:17-23` (delegator block) — duplicate.
* `application.rb:84-100` (mini `render`) — subset of inherited `render`.
* `application.rb:64-79` (rescue_from machinery and `app_rescue_from` indirection) — replaced by `render_error` + controller `error` action.
* `controller.rb:117-123` (delegator block, if Lifecycle hosts them) — moved into mixin.
* `controller.rb:305-318` (`controller_action_call`), if grep shows internal-only — replaced by `Controller.dispatch`.

Net framework reduction: ~50-60 lines, plus elimination of two parallel implementations of dispatch and render.

## Verification

* Existing spec suite passes with no changes (Part A is internal-only). Specs covering the old `rescue_from` macro need updating for Part B — replace with a spec that defines `MainController#error` and asserts it is invoked on raise.
* Manual smoke on `examples/demo/`: boot via `config.ru`, hit root, hit a nested route, trigger a 404, trigger a 500 in a controller (verify it routes to that controller's `error`), trigger a 500 in a router-level `before` (verify fallback to `Lux::Controller#error`).
* Confirm `Lux.app do before { ... }; map ...; end` still wires the `:before` callback.
* Confirm user-defined `ApplicationController < Lux::Controller` with its own `before_action` still fires per action, in the right order relative to the Application-level `:before`.
* Confirm an API controller defining `def error; render json: {...}; end` produces JSON errors when an action raises, and an HTML controller produces HTML errors — without any framework branching.
