# Lux::Controller

HTTP controllers. Rails-shaped (`before`, `before_action`, `render`,
`action`), but params are declared with the shared `opt` / `params do`
DSL - identical to `Lux::Api` and `Lux::Schema`.

## Small example

```ruby
class UsersController < Lux::Controller
  opt :name,  String, max: 30
  opt :email, type: :email
  def create
    User.create!(current.params.to_h)
    render json: { ok: true }
  end
end
```

* No `opt` declared on an action → params pass through untouched.
* `opt` lines above a `def` → strict: undeclared keys dropped, required
  keys validated, types coerced. Errors → 422 (JSON) or
  `current.var[:param_errors]` (HTML).

## Full example

```ruby
class BoardsController < ApplicationController
  layout :application

  before { @user = User.current or Lux.error.unauthorized }
  before_action { |name| Lux.log "running #{name}" }

  # class-level params: apply to every action in this class
  params do
    org_id type: :uuid                 # required for all actions
  end

  # method-level: union with the class-level set
  opt :name,   String, max: 30
  opt :tags?,  [String]
  def create
    board = @user.boards.create!(current.params.to_h)
    redirect_to "/boards/#{board.ref}"
  end

  # action with no opt lines: only org_id (class-level) applies
  def index
    @boards = @user.boards
  end

  # member actions inside `ref do` get renamed to <name>_ref
  ref do
    def show         # /boards/123          -> :show_ref, nav.ref = '123'
      @board = Board.find(nav.ref)
    end

    def edit         # /boards/123/edit     -> :edit_ref
      @board = Board.find(nav.ref)
    end
  end

  # default :error action - inherited from Lux::Controller. Override
  # for custom rendering. @error and @status are set before dispatch.
  def error
    render @status == 404 ? :not_found : :server_error
  end
end
```

## Render shortcuts

```ruby
render text: 'foo'
render plain: 'foo'
render html: '<h1>hi</h1>'
render json: { ok: true }
render javascript: 'alert(1)'
render xml: '<root />'
render template: 'main/custom'        # explicit template
render :foo, status: 201              # template by action-name + status
render html: '...', cache: 'key/v1'   # page-level cache + etag
```

## Callbacks

```ruby
before        do ... end   # before any action; runs once
before_action do |name| .. end  # before each action
before_render do ... end   # right before template render
after         do ... end   # after action
```

## Class DSL

```ruby
layout :application                   # template name, symbol, or lambda
template_root './apps/admin/views'    # override the default ./app/views
mock :show, :about                    # generate empty actions for templates
ref do ... end                        # group member actions (id-bearing URLs)

rescue_from do |err|                  # sugar: defines :error action
  render json: { error: err.message, status: @status }
end

# params / opt - see Small example above
```

## Instance helpers

| Method | Notes |
|--------|-------|
| `render`             | see Render shortcuts |
| `render_to_string`   | render without setting body |
| `redirect_to(path, flash = {})` | flash-aware redirect |
| `send_file(path, opts)` | file download / inline |
| `action(:other)` / `action('a/b#c')` | transfer to another action |
| `flash` / `flash.error 'msg'` | response flash |
| `helper` / `helper(:bar)` | helper module mix |
| `respond_to :js do ... end` | format-based dispatch |
| `cache(key, ttl:) { ... }` | request-level cache |
| `etag(*args)` | conditional 304 |
| `timeout(seconds)` | per-action timeout |
| `current` / `lux` / `params` / `nav` / `session` / `user` / `request` / `response` | lifecycle delegates |

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

## See also

* [`../schema/README.md`](../schema/README.md) - the `opt` line parser
* [`../api/README.md`](../api/README.md) - same DSL for JSON APIs
* [`../application/README.md`](../application/README.md) - routing
* [`AGENTS.md`](./AGENTS.md) - LLM guide
