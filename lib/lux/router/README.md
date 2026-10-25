# Lux::Router

One class owns routing, actions and rendering.
`Lux.router do ... end` class-evals into `Lux::Router`, the root router: one instance per request, running the page pipeline and its `route` block.
App routers subclass it (`class MainRouter < FrontendRouter`, file `app/routers/main_router.rb`) and add their own `before`, `layout`, `route` and actions.
`map` is the only routing word; it matches path segments and dispatches to an action, a router class, a `Lux::Api` or any Rack app.

`Lux do ... end` (inside Rack / `config.ru`) class-evals into `Lux::Router` and mounts it as the Rack app.
For specs use `Lux.router do ... end` (no Rack registration).

## Full example

```ruby
# app/routes.rb - class_eval on Lux::Router (the root router)
Lux.router do
  layout :promo                               # base layout (cattr), inherited by every router class

  before { UserSession.resolve }              # root pipeline hook (runs before CSRF/static)
  after  { EventLog.track(request.path) if user }   # root only, can rewrite the body

  rescue_from { |err| map 'promo#app_error' } # innermost router's handler wins, this is the fallback

  route do
    map 'api',    ApplicationApi              # Lux::Api / Rack class: env mount
    map 'logout', :logout                     # Symbol target = action method on THIS router
    map 'login',  'guest#login'               # mount GuestRouter, run action :login (route skipped)
    map 'dev',    'dev#auto'                  # mount DevRouter (web_common), run :auto
    map '/skills/:skill', 'skills#show'       # absolute pattern, :skill lands in params
    map %w[help faq], 'pages'                 # any-of segments, 'pages' = PagesRouter's route
    post? 'hook', :hook                       # verb predicates: get? head? post? put? patch? delete?
    subdomain 'app' do                        # subdomain scope: must render or 404s
      map MainRouter
    end
    map 'admin' do                            # block form: scope, nested maps see the rest of the path
      raise Lux.error.not_found unless user&.can&.admin?
      plugin_routes                           # every loaded plugin's routes.rb
      map AdminRouter
    end
    nav.load_models                           # sets @board, @space ... on this router; copied on mount; unknown ref 404s
    root 'main#index'                         # == map '', 'main#index' (cursor empty)
    map(user ? MainRouter : 'promo#auto')     # one arg = dispatch without matching
  end

  def logout                                  # root-owned: reachable only via an explicit map
    UserSession.destroy_session
    redirect_to '/', info: 'Signed out'       # redirect + flash, throws :done
  end

  def hook = render(json: { ok: true })
end

# app/routers/application_router.rb
class ApplicationRouter < Lux::Router
  before        { response.headers['content-security-policy'] = CSP }  # once per mount chain
  before_render { lux.browser.window[:app][:user] = user&.export }      # right before template render

  private

  def user = User.current                     # helpers stay private methods
end

# app/routers/main_router.rb
class MainRouter < FrontendRouter             # FrontendRouter < ApplicationRouter
  layout :main                                # class layout; views dir and helper follow it
  views  :app                                 # optional: views dir other than the layout name
  helper :main                                # optional: MainHelper for templates

  before do
    layout false if params[:layout] == 'false' # runtime switch for this request
    layout :dialog if request.xhr?
  end

  route do
    map :spaces, :ref, :admin do              # segments matched in sequence, :ref by type
      @space.can.update!                      # guard, then falls through (logged in debug)
    end
    map 'boards', :ref, 'edit', :edit_board   # no block: last arg is the target, the rest are segments
    map 'export',  :export
    map 'preview', :preview
    auto                                      # render main/<remaining path> template, else 404
  end

  def index                                   # resourceful empty path
    @boards = Board.can.all                   # implicit render main/index
  end

  allow :post                                 # verbs for the next def (default GET/HEAD/OPTIONS)
  opt :name, String, max: 100                 # params DSL for the next def
  def edit_board
    @board.update name: params[:name]
    flash.info 'Saved'                        # flash without redirect
    redirect_to @board.path
  end

  params do                                   # class-wide params schema (every action of this router)
    format? String
  end
  def export
    etag @space.updated_at                    # 304 short-circuit; render then sends body ''
    cache_control 'private, max-age=60'
    respond_to :csv do
      return send_file(@space.export_csv, name: 'space.csv')
    end
    render :export, layout: false             # explicit template, no layout
  end

  def preview
    html = render_to_string :card             # string only, does not end the router
    render text: html, content_type: :html, status: 200
  end

  def call                                    # actions may be named call/run; reached by map 'main#call'
    action params[:edit] ? :edit_board : :index   # transfer, no before rerun
  end

  def error                                   # rescue_from target (`map 'main#error'`); @error/@status are set
    render :error                             # app/views/main/error.haml
  end
end
```

## `map`

`map` takes what to match, then what to dispatch.
Every shape is listed here; anything else raises `ArgumentError` with the canonical form in the message.

| Form | Match | Dispatch |
|------|-------|----------|
| `map 'a' do ... end` | `/a` | block, nested routes see the rest of the path |
| `map :spaces, :ref, :admin do ... end` | the segments in sequence | block |
| `map 'a', :name` | `/a` | action `:name` on this router, opts become ivars |
| `map 'a', 'foo'` | `/a` | mount `FooRouter`, run its `route` (resourceful action when it has none) |
| `map 'a', 'foo#bar'` | `/a` | mount `FooRouter`, run action `:bar` |
| `map 'a', FooRouter` | `/a` | mount `FooRouter`, run its `route` |
| `map 'a', FooApi` | `/a` | `Lux::Api` mounted at the consumed prefix |
| `map 'a', RackApp` | `/a` | any class answering `.call(env)` |
| `map 'a', 'b', :ref, :name` | `/a/b/<id>` | last arg is the target |
| `map '/abs/:var', 'foo#bar'` | absolute path, `:var` into params | as above |
| `map %w[a b], 'foo'` | either segment | as above |
| `map FooRouter` / `map 'foo#bar'` / `map :name` | nothing | dispatch unconditionally |
| `root 'foo#bar'` | empty cursor | same as `map '', 'foo#bar'` |

Segments are Strings, Symbols, Regexps or Arrays (any of).
`:ref` matches a segment `nav.map_path` classified as an id, by type; a URL segment spelled `ref` is not one.
`'admin/users'` resolves to `Admin::UsersRouter`.

`subdomain 'x' do ... end` scopes on the subdomain and 404s when the block dispatches nothing.
`get? 'a', :x` / `post? { ... }` scope on the request verb.

## Mounting a router

A mounted router is a fresh instance of its class.
It receives a copy of the mounting router's instance variables (everything not prefixed `@_`), so data loaded in the root route (`nav.load_models`, `@org = ...`) is visible in its actions and templates.
Opts on `map` become ivars too, except `:only` / `:except`, which gate the actions it may run (404 otherwise).

```ruby
map 'users', 'admin/users', only: [:index], foo: :bar   # gated to :index, @foo = :bar
```

Then it runs its `before` hooks, minus those of classes it shares with the mounting router, so `ApplicationRouter`'s `before` runs once even when `MainRouter` mounts `AdminRouter`.
Then it runs the named action, or its `route` block, or a resourceful action when it has no `route`.
A mounted router that renders nothing answers 404.

A router class inherits its parents' `route`, never the root's.

## Actions

`action` runs one action: the `only` / `except` gates, the verb check, params validation, the method, then the implicit render of `<views dir>/<action>`.
Inside an action, `action :other` transfers without rerunning `before`.

Resourceful actions read the action name off the URL tail: the last segment that is not a classified id.

| URL                        | Action    | `nav.ref` |
|----------------------------|-----------|-----------|
| `/boards`                  | `:index`  | nil       |
| `/boards/edit`             | `:edit`   | nil       |
| `/boards/123`              | `:show`   | "123"     |
| `/boards/123/edit`         | `:edit`   | "123"     |
| `/boards/users/123`        | `:users`  | "123"     |
| `/boards/foo/bar`          | `:bar`    | nil       |

Only methods the app defined on a `Lux::Router` subclass are reachable this way, so a URL never dispatches into a framework method or a root router method.
Explicit `'router#action'` and Symbol targets bypass that check.

A router class may not define an action named after the routing / render DSL (`map`, `root`, `auto`, `action`, `render`, `redirect_to`, `layout`, ...); `method_added` raises `NameError`.
`call`, `run`, `error` and `user` are allowed.

`MainRouter.action(:index)` runs one action without routing (specs, console).

## Hooks

* `before` on the root: part of the page pipeline, before CSRF and static files.
* `before` on a router class: once per mount, before its route or action.
  A `before` that writes the body (render, redirect) ends the chain and the router.
* `before_render`: right before a template renders.
* `after`: root only, from `Response#render` after the body is set and before headers are written.
  `after` on a router class raises `ArgumentError`.

The 405 verb check runs after `before`, because the route picks the action.

## Rendering

`render` writes the body and throws `:done`, so code after it does not run.
`redirect_to` does the same.
`render_to_string` returns the markup and does not touch the response.

```ruby
render                                   # template named after the action
render :foo, status: 201                 # template by name + status
render 'shared/widget'                   # a slash skips the views dir
render text: 'ok' | plain: 'ok' | html: '...' | json: {...} | javascript: '...' | xml: '...'
render text: png_bytes, content_type: :png
render html: '...', cache: 'key/v1'      # page-level cache + etag
render_to_string :card
render_javascript :widget                # js content type, no layout
```

## Layout, views and helper

Three knobs decide what gets rendered, each defaulting to the `layout` name so you only set what differs:

| macro          | controls                                  | default       |
|----------------|-------------------------------------------|---------------|
| `layout :main` | layout file wrapping the page             | inherited     |
| `views :main`  | view subfolder under `template_root`      | layout name   |
| `helper :main` | helper module mixed into the template     | layout name   |

The class-level `layout` is inherited, so `layout :promo` in `Lux.router do` is the base of every router class.
The instance `layout :x` / `layout false`, callable in `before`, `route`, a `map` block or an action, switches the layout, views dir and helper for the rest of that router instance, `auto` included.
A mounted router starts from its own class layout.

## `auto`

`auto` renders the template matching the views dir plus the remaining route path (`app/views/<views>/<path>.{haml,md,erb}`, or `.../root.*`), else 404s.
It reads `lux.route.normalized_path`, so a classified id maps to a literal `ref` segment on disk: `/boards/abc123/edit` renders `app/views/boards/ref/edit.haml`.
Called from a route block it dispatches as action `:auto`, so the verb check and params validation run.
`auto_render` is the bare renderer for actions that pick their own moment.

```ruby
class DevRouter < FrontendRouter
  layout :dev

  route do
    map 'settings' do      # matches /dev/settings when mounted with map 'dev', DevRouter
      @tab = :settings
    end
    auto
  end
end
```

## Params and verbs

Params are declared with the shared `opt` / `params do` DSL, identical to `Lux::Api` and `Lux::Schema`.
Method-level `opt` lines are unioned with class-level `params`; the method wins on collision.
Undeclared keys are dropped, required keys validated, types coerced.

Every action accepts `GET`, `HEAD` and `OPTIONS` by default.
An `allow` line replaces that default with the verbs it lists; it is not additive.
Anything else answers `405 Method Not Allowed` with an `Allow` header.

```ruby
allow :post              # POST only (no GET)
allow :get, :post        # GET + HEAD + OPTIONS + POST
allow :any               # any verb (also: allow :all)
```

## Instance helpers

| Method | Notes |
|--------|-------|
| `redirect_to(path, flash = {})` | flash-aware redirect, ends the router |
| `send_file(path, opts)` | file download / inline |
| `flash` / `flash.error 'msg'` | response flash |
| `respond_to :js do ... end` | format-based dispatch |
| `cache(key, ttl:) { ... }` | request-level cache |
| `etag(*args)` / `cache_control 'private'` | conditional 304, cache header |
| `render_cache 'key'` | page cache for the next render |
| `authorize` / `is_authorized?` | `Lux::Policy::Authorize` |
| `current` / `lux` / `params` / `nav` / `session` / `user` / `request` / `response` | lifecycle delegates |

## Halting

A dispatch that writes the response body throws `:done`.
The root router catches it once, in `Router#resolve_routes`, so the first match ends routing.
A raw `response.body` does not throw, but the next `map` sees the body and stops instead of dispatching.

## Error handling

Errors anywhere in the pipeline land in `render_error`, which hands them to the innermost running router.
The rule:

1. The first error goes to that router's nearest `rescue_from` handler matching it, walking up to the root's; the handler takes it from there (usually `map 'main#error'`).
2. If the handler raises, the answer is a 500 dump: the framework page with the second error's message and backtrace in debug, a bare `500 Internal Server Error` otherwise.
3. No matching handler, or a handler that renders nothing, gets the default error screen: JSON (`{ status:, error: }`) for JSON requests, else `Lux::Router.default_error_page`.

A template exception raises like any other, so it reaches `rescue_from` too.
`@error` (the exception) and `@status` (the HTTP code: a `Lux::Error`'s own `status`, 403 for a policy denial, else 500) are set on the router first.
An action reached from a `rescue_from` handler skips the mounted router's `before`, the verb check and params validation.
`after` hooks do not run on error responses.

`rescue_from` is one macro (`Lux::RescueFrom`) on routers and APIs: `rescue_from { }` for any error, `rescue_from SomeError do ... end` for a class and its subclasses.

A query string or JSON body that cannot be parsed never reaches routing; it is answered with `400 Bad Request`.

## Request hygiene

`render_base` answers `GET`/`HEAD /healthcheck` with `ok` before reload, session, `before` hooks and routing.
A host without a letter (bare IP) and any request carrying `SOAPACTION` get a 403.
In dev, opening a page clears the terminal at most every 2s when stdout is a tty.

## Route cursor

`nav.path` is the canonical request path; `lux.route` is the per-request cursor over it, and the single owner of path matching.
`map` advances the cursor without mutating nav, so a router mounted under a prefix never repeats that prefix.

| | |
|---|---|
| `lux.route.path`            | remaining path after consumed segments |
| `lux.route.root`            | first remaining segment |
| `lux.route.child`           | second remaining segment |
| `lux.route.consumed`        | segments before the cursor |
| `lux.route.match?(x)`       | does the cursor root match? String / Symbol / Regexp / Array |
| `lux.route.start_with?(*s)` | does the cursor start with these segments? |
| `lux.route.capture('/a/:b')`| absolute pattern match from the URL root; captures hash or nil |
| `lux.route.with_scope(n)`   | enter a scope for the block (used by `map`) |

`-` and `_` are the same character to every one of those matchers, and the comparison is the only place it happens; `nav.path` keeps the URL's original spelling.

## CLI

```bash
lux routes          # print the route tree, mounted routers replayed in place
lux routes -v       # add source location per entry
```

## See also

* [`../schema/README.md`](../schema/README.md) - the `opt` line parser
* [`../api/README.md`](../api/README.md) - same params DSL for JSON APIs
* [`../current/README.md`](../current/README.md) - `nav`, `route`, request state
* [`../response/README.md`](../response/README.md) - response builder
