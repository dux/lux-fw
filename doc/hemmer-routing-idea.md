> STATUS: design proposal - NOT implemented, and partly overtaken by events.
> Describes a possible future router, not current behavior. For current
> behavior read [`../lib/lux/application/README.md`](../lib/lux/application/README.md).
>
> Several things this proposal wanted to delete are already gone, achieved by
> trimming the existing router rather than replacing it (see
> [`./migration-routing.md`](./migration-routing.md)):
>
> * `Lux::Controller::ACTION_ROUTES`, the per-action `route '/path'` macro,
>   `action_route_match?` and `resolve_action_routes` - deleted. Dispatch is a
>   single pass through the `routes` callbacks.
> * The `_ref` action rename and the `ref do` macro - deleted. Resourceful
>   dispatch resolves to the last non-`:ref` segment and the action reads
>   `nav.ref`.
> * Path matching is no longer spread across four matchers; `Lux::Application::Route`
>   owns `match?` / `start_with?` / `capture` and the controller `filter` tree
>   walks the same cursor as `map`.
>
> What remains genuinely unsolved is the **namespace-scoped `before`** and the
> **plugin-appends-to-an-existing-namespace** problem in the "Why" below. Those
> are the parts worth re-reading if this is ever picked up.

# Hammer-style routing idea

## Why

Today routes live in a single block evaluated per-request against a path
cursor. The model is *positional and imperative*:

* `map 'admin' do ... end` walks `lux.route` forward by one segment, then
  re-evaluates inside the block. Source order decides precedence.
* `before` / `before_action` are controller-class concepts; you cannot say
  "run this before anything mounted under `/admin`" without writing a
  router-level `before` that re-checks the path - or wrapping the whole
  namespace in `map 'admin' do ... end` and putting the guard on the first
  line, which is what apps do today.
* Plugins extend by re-eval'ing their own `routes.rb`, which means a plugin
  cannot append to an existing namespace without the host file calling
  `plugin_route` at the right spot.

We want routing to behave like Hammer/Rake namespaces:

```ruby
ns :admin do
  before { require_admin! }
end

ns :admin do
  get '/users',     'admin/users#index'
  post '/users',    'admin/users#create'
  ns :reports do
    root 'admin/reports#index'
  end
end

# in a plugin, loaded later, with no ordering coordination:
ns :admin do
  mount Authcog::Engine, at: '/auth'
end
```

All three blocks merge into the same `:admin` node. Order of declaration
does not affect dispatch.

## Model

A single global tree:

```
Registry (root node)
 ├── before:   [proc, proc, ...]
 ├── routes:   [{ verb:, pattern:, target:, opts: }, ...]
 ├── after:    [...]
 └── children: { "admin" => Node, "api" => Node, ... }
```

`Node` is the same shape as the root. `ns :name do ... end` looks up (or
creates) a child by `name.to_s` and `instance_evals` the block on that
child.

### Patterns

Every route carries an *unambiguous, complete* pattern relative to its
node, e.g. `'/users/:ref'`, `'/users/:ref/edit'`, `'/'` (root). No cursor,
no "match any segment then fall through." A pattern collision at
registration time raises - this replaces today's "first match wins"
silent shadowing.

### Targets

Same shapes `call` already accepts:

* `'controller#action'` - explicit
* `'controller'`        - resourceful (keep `resourceful_action` logic)
* `Klass` / `[Klass, :action]`
* `Proc` / Rack app

### Controllers shrink

> Written when controllers still had a `route '/path'` macro. That macro is
> gone - URLs are declared in the router only - so there is nothing left to
> desugar here. The paragraph below is the part that still matters.

Controller `before_action` / `after` callbacks stay (they are per-action,
not per-path), but the common "before-everything-under-/admin" use case
migrates to `ns :admin do; before { ... }; end`. Today that is spelled
`map 'admin' do` with the guard as the first statement in the block, which
works but couples the guard to declaration order and to one call site.

### Resolution

At request time, walk path segments:

1. Start at the root node.
2. For each segment, descend into the child whose key matches. Push that
   node onto a stack along the way.
3. After descent, the remainder of the path is matched against
   `node.routes` patterns (longest/most-specific wins, deterministic by
   structure - no source order).
4. On match: run every `before` from root -> matched node (in tree order),
   then dispatch the target, then `after` from matched -> root.
5. No match anywhere: 404.

`before` is *namespace-scoped*, not declaration-scoped, which is the whole
point - it doesn't matter whether `before` was registered before or after
the routes inside the same `ns`.

### What we keep

* `map` and `call` as the imperative escape hatch inside a route target
  (proc/block). The DSL becomes declarative, but inside a matched handler
  the existing `call 'foo#bar'` / `lux.response.body ...` still work.
* `plugin_route` / `plugin_routes` - same idea, just that plugin routes
  now register into the shared tree instead of evaluating in place.
* `rescue_from` (app-level), `subdomain` - orthogonal.

### What we drop

* `lux.route` cursor + `with_scope` - patterns are absolute relative to
  their node, no incremental walking. **Note:** the cursor has since grown
  into the single owner of path matching (`match?` / `start_with?` /
  `capture`) and is what the controller `filter` tree walks, so dropping it
  is a bigger cut today than it was when this was written.
* The `routes do ... end` callback shape on `Lux::Application` -
  registration is load-time, not request-time. (Class-level `map`/`root`
  in `Lux.app do ... end` becomes top-level calls into the registry.)
  This is the real cost of the proposal: every app router is an imperative
  per-request pipeline (`general_rules`, `load_objects`, `admin_routes`,
  then a `call 'main#auto'` catch-all), not a static table.

Already dropped, without this refactor: `Lux::Controller::ACTION_ROUTES`
and the `resolve_action_routes` / `resolve_routes` two-pass dispatch.

## Start plan

Tracer-bullet first. Build the new registry alongside the existing
router, port one app, then swap and delete the old code. No
backwards-compat shims.

### Step 1 - Registry skeleton

`lib/lux/router/node.rb`:

```ruby
class Lux::Router::Node
  attr_reader :children, :routes, :before_hooks, :after_hooks
  def initialize; @children = {}; @routes = []; @before_hooks = []; @after_hooks = []; end
  def ns(name, &block); (@children[name.to_s] ||= Node.new).instance_eval(&block); end
  def before(&b); @before_hooks << b; end
  def after(&b);  @after_hooks  << b; end
  def get(pattern,  target, **opts); add(:get,  pattern, target, opts); end
  def post(pattern, target, **opts); add(:post, pattern, target, opts); end
  # ... put, patch, delete, head
  def any(pattern,  target, **opts); add(:any,  pattern, target, opts); end
  def root(target,  **opts);         add(:get,  '/',     target, opts); end
  def match(pattern, target, verb: :any, **opts); add(verb, pattern, target, opts); end

  private

  def add(verb, pattern, target, opts)
    if existing = @routes.find { |r| r[:verb] == verb && r[:pattern] == pattern }
      raise "Route collision: #{verb.upcase} #{pattern} already registered -> #{existing[:target].inspect}"
    end
    @routes << { verb:, pattern:, target:, opts: }
  end
end
```

`lib/lux/router/registry.rb` - singleton root node, top-level DSL
re-exports (`Lux::Router.ns`, `Lux::Router.get`, ...).

### Step 2 - Pattern matcher

Compile pattern strings to a small matcher object once at registration:

```ruby
'/users/:ref/edit' -> Matcher(['users', :ref, 'edit'])
```

`Matcher#match(path_parts)` returns `nil` or `{ ref: 'abc' }`. No regex
unless we hit a feature we can't do with segment compare.

Specificity ordering at lookup time: literal segments outrank captures,
longer paths outrank shorter. Deterministic - no source order.

### Step 3 - Resolver

`Lux::Router.resolve(request)`:

1. Tokenize `lux.nav.path` into segments.
2. Walk the tree as far as the path's leading segments match child
   names; collect `before`/`after` hooks along the way.
3. At the deepest matched node, scan `node.routes` for a pattern match
   on the remaining segments, filtered by verb.
4. Return `{ target:, params:, before:, after: }` or `nil`.

Drop into `Application#render_base` in place of `resolve_routes`.

### Step 4 - ~~Controller `route` macro -> registry write~~

Obsolete. The controller `route` macro and `ACTION_ROUTES` are gone; there
is nothing to migrate. `@_action_allows` (the `allow` verb contract) stays
on the controller either way - it gates the action, not the URL.

### Step 5 - Top-level DSL

Make `Lux.app do ... end` evaluate its body against the root node, so:

```ruby
Lux.app do
  before { ... }       # root-level before, runs on every request
  root 'main#index'
  ns :admin do
    before { require_admin! }
    get '/users', 'admin/users#index'
  end
end
```

works without a `routes do` wrapper. The existing `ROUTING_DSL` /
`@class_callbacks_routes` machinery on `Lux::Application` goes away.

### Step 6 - Port one app, prove it

Pick the smallest internal app (probably `plugins/web_common`) and rewrite
its `routes.rb` against the new registry. Run it under the new resolver,
gate the old resolver behind a config flag during the transition.

### Step 7 - Delete

Once the canary is green:

* delete `lib/lux/application/lib/routes.rb` (`map`, cursor, etc.)
* delete `lux.route` cursor + `with_scope` - and with it `match?` /
  `start_with?` / `capture`, so the controller `filter` tree needs a
  replacement built on node patterns first
* simplify `Lux::Controller`: drop controller-level `before` if `ns`-level
  `before` covers the use case; otherwise keep `before_action` as the
  per-action-name hook

## Open questions

* **Resourceful dispatch**: today `map 'users'` to `UsersController`
  derives the action from the last non-`:ref` segment. Worth preserving as
  `mount Klass, at: '/users'` sugar that registers the standard routes? Or
  force explicit declaration? (Note: no app uses resourceful dispatch, so
  "force explicit" costs nothing today.)
* **Controller `filter` trees**: the heaviest real usage in app code is the
  nested `filter :seg do` tree, which is a path-scoped `before` in
  everything but name. `ns`-scoped `before` is meant to replace it - confirm
  it can express the same thing (including `:ref` segments) before cutting.
* **Plugin mount points**: should `mount Plugin::Foo, at: '/foo'` graft
  the plugin's whole subtree under that key, or should plugins always
  `ns :foo` themselves and assume the host mounts under root? Tree graft
  is cleaner; plugin can still be moved by the host with one line.
* **Subdomain / verb scoping**: today both are top-level checks. Should
  `ns` accept `subdomain:` / `verb:` constraints, or stay path-only and
  push verb/subdomain into route entries?
