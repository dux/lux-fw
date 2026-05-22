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
    @user = User.find_by_token(@api.bearer) or @api.error 'auth required', status: 401
  end

  rescue_from Sequel::NoMatchingRow do |err|
    @api.response.error 'Not found', status: 404
  end

  # --- collection actions ----------------------------------------------

  desc 'List boards'                                    # `desc` opts the next def in as an endpoint
  define :list do                                       # `define` registers explicitly (proc/lambda)
    proc { @user.boards.all }
  end

  desc 'Create a board'
  params do
    name   String, max: 30
    tags?  [String]
  end
  def create
    @user.boards.create!(@api.params.to_h)
  end

  # --- member actions (require ref) ------------------------------------

  ref do
    before { @board = @user.boards.find(@ref) }

    desc 'Get one board'
    def show; @board; end

    desc 'Update a board'
    params do
      name?  String, max: 30
    end
    def update
      @board.update(@api.params.to_h)
      @board
    end

    desc 'Delete a board'
    allow :delete                                        # additional verb (default POST)
    def destroy
      @board.destroy
      message 'deleted'                                  # plain message body
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

## Endpoint registration

A plain `def` inside an Api class is registered as an endpoint **only if**
preceded by a `desc` line (the opt-in marker). Without `desc`, the method
is treated as a plain Ruby helper.

`define :name do ... end` always registers (with or without `desc`). Use
it when you want to wire a Proc/lambda explicitly.

To opt out class-wide (legacy code): `def_registration_strict false`.

## DSL reference

| Class method | Purpose |
|--------------|---------|
| `desc 'text'`           | description for the next endpoint |
| `detail 'longer'`       | longer description (Markdown) |
| `icon File.read(...)`   | SVG icon for the explorer |
| `class_desc` / `class_detail` | apply to whole class |
| `params do ... end`     | param schema for the next endpoint |
| `schema_ref :name`      | reference a top-level model schema instead of inline params |
| `allow :get, :put`      | additional HTTP methods (default POST) |
| `unsafe`                | endpoint callable without bearer token |
| `define name do; proc {...}; end` | explicit endpoint registration |
| `annotation :flag do ... end` | custom marker, used like `unsafe` |
| `plugin :name do ... end` / `plugin :name` | reusable behavior |
| `ref do ... end`        | member endpoints (`@ref` set from request) |
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
* [`AGENTS.md`](./AGENTS.md) - LLM guide
