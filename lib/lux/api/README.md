# Lux::Api

JSON-RPC-ish API classes. Same `params do` / shared schema DSL as
`Lux::Controller`, plus:

* automatic JSON request/response
* introspection: `/sys/web` (interactive explorer), `/sys/openapi`,
  `/sys/postman`, `/sys/AGENTS.md` (LLM-readable API surface)
* `desc` / `detail` / `icon` annotations rendered in the explorer
* `ref do ... end` for member endpoints
* `rescue_from`, `before`, `after`, `define`, `annotation`, `plugin`

## Full example

```ruby
class BoardsApi < ApplicationApi
  class_desc 'Board management'
  icon File.read('./app/assets/icons/board.svg')
  mount_on '/api'                                       # optional; default '/api'
  documented                                            # show in /sys/openapi
  unsafe                                                # endpoints callable without bearer

  before do
    @user = User.find_by_token(@api.bearer) or response.error('auth required', status: 401)
  end

  rescue_from Sequel::NoMatchingRow do |err|
    @api.response.error 'Not found', status: 404
  end

  # --- collection actions (define, at class root) ----------------------

  define :list do
    desc 'List boards'                                  # desc is optional metadata
    proc { @user.boards.all }
  end

  define :create do
    desc 'Create a board'
    params do
      name   String, max: 30
      tags?  [String]
    end
    proc { @user.boards.create!(@api.params.to_h) }
  end

  # --- member actions (define inside ref do; @board loaded once) -------

  ref do
    before { @board = @user.boards.find(@ref) }

    define :show do
      desc 'Get one board'
      proc { @board }
    end

    define :update do
      desc 'Update a board'
      params do
        name?  String, max: 30
      end
      proc do
        @board.update(@api.params.to_h)
        @board
      end
    end

    define :destroy do
      desc 'Delete a board'
      allow :delete                                       # additional verb (default POST)
      proc do
        @board.destroy
        message 'deleted'                                 # plain message body
      end
    end
  end

  # --- references / utilities ------------------------------------------

  schema_ref :user                                       # reuse a Lux.schema instead of inline params

  annotation :flag do |args|                             # custom marker, used like `unsafe`
    # ...
  end

  plugin :pagination do                                  # reusable behavior
    # ...
  end
end

# In controller-style endpoints you can also reach for:
#   send_file(path, opts)   send_data(blob, opts)
#   super!                  # call the superclass implementation
```

Call:
```
POST /api/boards/create
{ "name": "todo", "tags": ["work"] }
```

## Creating a visible API endpoint

Endpoints are created in **exactly one way** - the `define` family. A plain `def` is
**never** an endpoint; it is always a plain Ruby helper.

* `define :name do ... end` at class root -> a **collection** action
* `define_ref :name do ... end` -> a **member** action (request carries a resource id)
* `define :name do ... end` inside `ref do ... end` -> also a member action; use the
  block form when several member actions share a `before` (e.g. loading the record)

The block configures the action with optional `desc` / `detail` / `params` / `allow` /
annotations (metadata only) and **returns a `Proc`** - the action body.

```ruby
define :create do          # collection endpoint
  desc 'Create a board'    # optional - metadata, not required
  params { name String }
  proc { Board.create(params.to_h) }
end

define_ref :show do        # member endpoint (resource id in @ref)
  proc { @board }
end

def helper                 # plain def -> never an endpoint
  ...
end
```

`desc` is optional metadata for the explorer/docs - it no longer turns a method into an
endpoint. Private and protected methods are never endpoints.

## DSL reference

| Class method | Purpose |
|--------------|---------|
| `desc 'text'`           | optional description for the next define (metadata only) |
| `detail 'longer'`       | longer description (Markdown) |
| `icon File.read(...)`   | SVG icon for the explorer |
| `class_desc` / `class_detail` | apply to whole class |
| `params do ... end`     | param schema for the next endpoint |
| `schema_ref :name`      | reference a top-level model schema instead of inline params |
| `allow :get, :put`      | additional HTTP methods (default POST) |
| `unsafe`                | endpoint callable without bearer token |
| `undocumented`          | endpoint stays callable but is hidden from OpenAPI/Postman/introspect output |
| `define name do; proc {...}; end` | collection endpoint (at class root) |
| `define_ref name do; proc {...}; end` | member endpoint (no enclosing `ref do` needed) |
| `annotation :flag do ... end` | custom marker, used like `unsafe` |
| `plugin :name do ... end` / `plugin :name` | reusable behavior |
| `ref do ... end`        | group member endpoints + share a `before` (`@ref` from request) |
| `before do ... end` / `after do ... end` | callbacks |
| `rescue_from Error do ... end` | per-exception handling |
| `mount_on '/api'`       | API root path |
| `documented`            | mark this API public in generated docs |

## Instance helpers (inside endpoints)

| Method | Notes |
|--------|-------|
| `@api.params`           | validated + coerced params |
| `@api.bearer`           | Bearer token if present |
| `@ref`                  | resource id for `ref do` endpoints |
| `response.error 'msg', status: N` | error response |
| `error 'msg'`           | raise + render error |
| `message 'text'`        | render plain message |
| `send_file(path, opts)` / `send_data(blob, opts)` | file download |
| `super!`                | call superclass implementation |

## Built-in introspection

* `/<mount_on>/sys/web`        - interactive HTML explorer (Lux::Api::Web)
* `/<mount_on>/sys/openapi.json` - OpenAPI 3 schema
* `/<mount_on>/sys/postman.json` - Postman collection
* `/<mount_on>/sys/AGENTS.md`   - LLM-readable surface of every endpoint
* root `/` GET → redirect to the explorer

## See also

* [`../controller/README.md`](../controller/README.md) - same DSL, HTML-shaped
* [`../schema/README.md`](../schema/README.md) - the underlying schema DSL
* [`../type/README.md`](../type/README.md) - named types used in `params do`
