# Lux::Controller

HTTP controllers. Rails-shaped (`before`, `before_action`, `render`,
`action`), but params are declared with the shared `opt` / `params do`
DSL - identical to `Lux::Api` and `Lux::Schema`.

Actions default to `GET` (plus `HEAD`). To accept other verbs, declare
the full verb set with `allow` above the `def` - `allow` is not additive,
it replaces the default. See [Allowed HTTP verbs](#allowed-http-verbs) below.

`Lux::Controller` is the base class for subclassing; per-action helpers
hang off `current` / `lux` / `params` / `nav` etc. inside the action.

## Full example

```ruby
class BoardsController < ApplicationController
  layout :application
  template_root './apps/admin/views'           # override default ./app/views

  before { @user = User.current or Lux.error.unauthorized }
  before_action { |name| Lux.log "running #{name}" }
  before_render { ... }                        # right before template render
  after         { ... }                        # after action

  # rescue_from is sugar that defines :error action
  rescue_from do |err|
    render json: { error: err.message, status: @status }
  end

  # class-level params apply to every action in this class
  params do
    org_id type: :uuid
  end

  # method-level opt is unioned with class-level; method wins on collision.
  # Strict mode: undeclared keys dropped, required keys validated, types coerced.
  opt :name,  String, max: 30
  opt :tags?, [String]
  allow :post                                  # POST only - replaces the GET default
  def create
    board = @user.boards.create!(current.params.to_h)
    redirect_to "/boards/#{board.ref}"
  end

  # No opt lines: only class-level params apply
  def index
    @boards = @user.boards
  end

  # Member actions inside ref do { ... } are renamed to <name>_ref
  ref do
    def show         # /boards/123        -> :show_ref, nav.ref = '123'
      @board = Board.find(nav.ref)
    end

    def edit         # /boards/123/edit   -> :edit_ref
      @board = Board.find(nav.ref)
    end
  end

  mock :show, :about                           # generate empty actions for templates

  # Default :error action, inherited from Lux::Controller; override for
  # custom rendering. @error and @status are set before dispatch.
  def error
    render @status == 404 ? :not_found : :server_error
  end

  # --- render shortcuts ---------------------------------------------------
  def all_renders
    render text: 'foo'
    render plain: 'foo'
    render html: '<h1>hi</h1>'
    render json: { ok: true }
    render javascript: 'alert(1)'
    render xml: '<root />'
    render template: 'main/custom'             # explicit template
    render :foo, status: 201                   # template by action-name + status
    render html: '...', cache: 'key/v1'        # page-level cache + etag
    render_to_string :show                     # render without setting body
  end

  # --- dispatch / responses -----------------------------------------------
  def show
    redirect_to '/foo', info: 'done'           # flash-aware redirect
    send_file('./tmp/report.pdf', inline: true)
    action(:other)                             # transfer within this controller
    action('admin/users#index')                # transfer cross-controller
    flash.error 'oops'                         # response flash
    respond_to :js do |fmt|                    # format-based dispatch
      fmt.html { render :show }
      fmt.json { render json: @board }
    end
    cache(key, ttl: 60) { ... }                # request-level cache
    etag(@board)                               # conditional 304
    timeout(5)                                 # per-action timeout (seconds)
    helper(:bar)                               # mix in BarHelper
  end
end
```

## Render shortcut quick-reference

```ruby
render text: 'foo' | plain: 'foo' | html: '...' | json: {...}
render javascript: 'alert(1)' | xml: '<root />'
render template: 'main/custom'
render :action_name, status: 201
render html: '...', cache: 'key/v1'
```

## Allowed HTTP verbs

Every action accepts `GET` and `HEAD` by default. An `allow` line REPLACES
that default with the verbs it lists - it is not additive. Anything not in
the set returns `405 Method Not Allowed` (with a developer hint in dev mode).

```ruby
allow :post              # POST only (no GET)
def create; end

allow :get, :post        # GET + HEAD + POST (declare both explicitly)
def upsert; end

allow :post, :patch      # POST + PATCH only
def update; end

allow :any               # any verb (also: allow :all)
def webhook; end
```

`allow` placement mirrors `opt` / `desc`: above the `def` it applies to.
HEAD piggybacks on GET only when GET is in the declared set. The `:error`
action is implicitly `:any` so error rendering never 405s.

The same `allow` word exists in `Lux::Api`, with the inverse default: API
endpoints default to `POST`, and `allow :get` adds GET on top. Same word,
same shape, the framework-appropriate default per system.

## Per-action routes

Actions can declare their own absolute URLs with `route`. The annotation
sits above the `def` (same opt-the-next-def-in shape as `opt` / `allow`),
multiple lines stack as URL aliases for the same handler, and resolution
happens after the application's `before` filters run - so any user-loading
filter has already populated ivars by the time the action dispatches.

```ruby
class UsersController < Lux::Controller
  route '/users'
  def index; end                       # GET /users

  route '/u/:slug'
  allow :get, :post
  def by_slug; end                     # GET or POST /u/anything

  route '/users/new'
  route '/users/create'                # two URLs, one handler
  allow :get, :post
  def create; end

  ref do
    route '/users/:ref/dashboard'
    def dashboard; end                 # method becomes :dashboard_ref;
                                       # nav.ref bound from the :ref capture
  end
end
```

Rules:

* Paths must be absolute (start with `/`). They are not scoped under any
  `routes do` mount point.
* Captures (`:name`) land in `nav.params[:name]`. A `:ref` capture also
  binds `nav.ref` for the resourceful convenience.
* `allow` still governs verb enforcement - `route` is path-only. No `allow`
  means GET + HEAD only.
* `ref do` placement is what triggers the `_ref` method rename. A `route`
  above a `def` inside `ref do` follows the method to the `_ref` key.
* Per-action routes take priority over `routes do` resourceful dispatch.
  Within the per-action registry, source/load order is match order; first
  match wins.

Subdomain routing and wildcards/regex paths are not supported here -
keep using `routes do` for those.

## Routing primer

URLs map to actions resourcefully when `nav.path(:ref) { ... }` is set in
a `before` filter (see [`../application/README.md`](../application/README.md)
for the routing DSL).

| URL                       | Action       | `nav.ref` |
|---------------------------|--------------|-----------|
| `/users`                  | `:root`      | nil       |
| `/users/edit`             | `:edit`      | nil       |
| `/users/123`              | `:show_ref`  | "123"     |
| `/users/123/edit`         | `:edit_ref`  | "123"     |
| `/users/foo/bar`          | `:foo`       | nil       |
| `/users/123/foo/bar`      | `:foo_ref`   | "123"     |

`def NAME` inside `ref do ... end` becomes `:NAME_ref`. Template lookup
tries `<name>_ref.haml` then falls back to `<name>.haml`.

## Instance helpers

| Method | Notes |
|--------|-------|
| `render`             | see shortcuts |
| `render_to_string`   | render without setting body |
| `redirect_to(path, flash = {})` | flash-aware redirect |
| `send_file(path, opts)` | file download / inline |
| `action(:other)` / `action('a/b#c')` | transfer to another action |
| `flash` / `flash.error 'msg'` | response flash |
| `helper(:bar)` | mix in `BarHelper` |
| `respond_to :js do ... end` | format-based dispatch |
| `cache(key, ttl:) { ... }` | request-level cache |
| `etag(*args)` | conditional 304 |
| `timeout(seconds)` | per-action timeout |
| `current` / `lux` / `params` / `nav` / `session` / `user` / `request` / `response` | lifecycle delegates |

## See also

* [`../schema/README.md`](../schema/README.md) - the `opt` line parser
* [`../api/README.md`](../api/README.md) - same DSL for JSON APIs
* [`../application/README.md`](../application/README.md) - routing
