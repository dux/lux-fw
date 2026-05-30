> STATUS: design proposal - NOT implemented. Describes a possible future router, not current behavior.

# Hammer-style routing idea

## Why

Today routes live in a single block evaluated per-request against a path
cursor. The model is *positional and imperative*:

* `map 'admin' do ... end` walks `lux.route` forward by one segment, then
  re-evaluates inside the block. Source order decides precedence.
* Per-controller `route` annotations are a separate registry
  (`Lux::Controller::ACTION_ROUTES`) checked before the routes block.
* `before` / `before_action` are controller-class concepts; you cannot say
  "run this before anything mounted under `/admin`" without writing a
  router-level `before` that re-checks the path.
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

Controller-side `route` macros become sugar that registers at load time:

```ruby
class UsersController < Lux::Controller
  route '/users/:ref', verb: :get
  def show; ...; end
end
```

becomes, at class-eval time:

```ruby
Lux::Router.ns(:_root).get('/users/:ref', [UsersController, :show])
```

Controller `before_action` / `after` callbacks stay (they are per-action,
not per-path), but the common "before-everything-under-/admin" use case
migrates to `ns :admin do; before { ... }; end`. That alone should let us
delete most of the controller-level `before` plumbing.

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
  their node, no incremental walking.
* `Lux::Controller::ACTION_ROUTES` global - rolled into the same tree.
* `resolve_action_routes` / `resolve_routes` two-pass dispatch -
  single tree walk does both.
* The `routes do ... end` callback shape on `Lux::Application` -
  registration is load-time, not request-time. (Class-level `map`/`root`
  in `Lux.app do ... end` becomes top-level calls into the registry.)

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

### Step 4 - Controller `route` macro -> registry write

Move `params_dsl.rb`'s `route 'path', verbs: ...` so that on
`method_added` it calls `Lux::Router.add(verb, pattern, [self, name])`
instead of pushing to `ACTION_ROUTES`. Verb metadata moves out of
`@_action_allows` (still needed for resourceful dispatch when no `route`
was declared, until that path is removed too).

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

works without a `routes do` wrapper. The existing
`@class_callbacks_routes` machinery in `application.rb:36-73` goes away.

### Step 6 - Port one app, prove it

Pick the smallest internal app (probably `plugins/web_common`) and rewrite
its `routes.rb` against the new registry. Run it under the new resolver,
gate the old resolver behind a config flag during the transition.

### Step 7 - Delete

Once the canary is green:

* delete `lib/lux/application/lib/routes.rb` (`map`, cursor, etc.)
* delete `Lux::Controller::ACTION_ROUTES`, `resolve_action_routes`,
  `action_route_match?`
* delete `lux.route` cursor + `with_scope`
* simplify `Lux::Controller`: drop controller-level `before` if `ns`-level
  `before` covers the use case; otherwise keep `before_action` as the
  per-action-name hook

## Open questions

* **Resourceful dispatch**: today `map 'users'` to `UsersController`
  auto-derives `:index`/`:show`/`:edit`/... from the remaining path.
  Worth preserving as `mount Klass, at: '/users'` sugar that registers
  the standard 7 routes? Or force explicit declaration?
* **`ref do`**: the `_ref` action rename is convenient but tightly coupled
  to the cursor model. If routes are explicit patterns, `_ref` actions
  can just declare their own pattern (`'/users/:ref/edit'`) and the rename
  dance goes away. Likely a clean delete.
* **Plugin mount points**: should `mount Plugin::Foo, at: '/foo'` graft
  the plugin's whole subtree under that key, or should plugins always
  `ns :foo` themselves and assume the host mounts under root? Tree graft
  is cleaner; plugin can still be moved by the host with one line.
* **Subdomain / verb scoping**: today both are top-level checks. Should
  `ns` accept `subdomain:` / `verb:` constraints, or stay path-only and
  push verb/subdomain into route entries?
