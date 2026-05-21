# Lux::Api - agent guide

JSON-RPC-ish API classes. Same `params do` / schema DSL as
`Lux::Controller`. **Use the same line forms; do not invent new ones.**

## Canonical example

```ruby
class BoardsApi < ApplicationApi
  class_desc 'Board management'

  before do
    @user = User.find_by_token(@api.bearer) or @api.error 'auth required', status: 401
  end

  desc 'List boards'
  define :list do
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

  ref do
    before { @board = @user.boards.find(@ref) }

    desc 'Update a board'
    params do
      name? String, max: 30
    end
    def update
      @board.update(@api.params.to_h)
      @board
    end

    desc 'Delete a board'
    allow :delete
    def destroy
      @board.destroy
      message 'deleted'
    end
  end

  rescue_from Sequel::NoMatchingRow do |err|
    @api.response.error 'Not found', status: 404
  end
end
```

## Class-level markers

| Marker | Effect |
|--------|--------|
| `documented`     | mark class public in generated docs/explorer |
| `class_desc`     | description for the whole API class |
| `class_detail`   | longer/markdown description for the class |
| `mount_on '/api'`| path prefix for this Api when auto-mounted |

## Per-endpoint markers (before a `def` or `define`)

| Marker | Effect |
|--------|--------|
| `desc 'text'`            | one-line description (also: opt-in marker for `def`) |
| `detail 'longer markdown'` | expanded description rendered in the explorer |
| `icon File.read('x.svg')`  | SVG icon for the explorer card |
| `params do ... end`      | param schema (shared DSL with `Lux::Schema`) |
| `schema_ref :user`       | reference a top-level model schema by name |
| `allow :get, :put`       | additional HTTP methods (default POST) |
| `unsafe`                 | endpoint callable WITHOUT bearer token |

Check `@api.method_opts[:unsafe]` inside `before` callbacks to skip
auth for endpoints flagged with `unsafe`:

```ruby
before do
  unless @api.method_opts[:unsafe]
    @user = User.find_by_token(@api.bearer) or @api.error 'auth required', status: 401
  end
end
```

## Legacy DSL aliases (Joshua-compatible)

* `collection do ... end` - equivalent to defining at class root
* `member do ... end`     - equivalent to `ref do ... end`

Don't introduce them in new code; use `ref do` and define collection
actions at class root. Recognize them when reading existing code.

## Rules

* **Endpoint registration:** a plain `def` is registered only if preceded
  by `desc`. Use `define :name do; proc {...}; end` when you want explicit
  registration without a description.
* **Params DSL is identical to controllers.** Inside `params do`, the same
  shortcut lines (`name String, max: 30`, `email? type: :email`) work.
* **Validation runs in `parse_api_params`** (`base_instance.rb:103`) before
  the endpoint body, halting with structured errors on failure.
* **Member endpoints inside `ref do`**: `@ref` is set from the request id.
  Methods inside become `:<name>_ref` and dispatch when an id is present.
* **`@api`** is the request envelope (`params`, `bearer`, `method_opts`,
  `request`, `response`, ...). Available in every endpoint.
* **HTTP method default is POST** for RPC-style. Allow others with
  `allow :get`, `allow :get, :put`, or per-define `define get: :show`.
* **Error responses:** `@api.error 'msg', status: 401` or `error 'msg'`
  (raises `Lux::Api::Error`). Both halt cleanly.
* **Bearer extraction:** `Authorization: Bearer <token>` header, or
  `?api_token=` query, or `{ token: ... }` in JSON-RPC body. All land in
  `@api.bearer`.

## Don't

* Add custom JSON serialization in every endpoint - return Ruby values
  (hash/array/object responding to `to_h`), the framework JSON-encodes.
* Hand-roll validation. Use `params do` or `schema_ref :name` to reference
  an existing schema.
* Define `def foo` without a `desc` and expect it to be an endpoint -
  it's a private helper unless `desc` precedes.
* Touch `@@opts` directly - use the DSL methods (`desc`, `params`, ...).

## Introspection routes (mount under your API root)

`/<root>/sys/web` (explorer), `/sys/openapi.json`, `/sys/postman.json`,
`/sys/AGENTS.md`. These come for free; just mount `Lux::Api` and apps
get them automatically.

## See also

* [`Lux::Controller` AGENTS](../controller/AGENTS.md)
* [`Lux::Schema` AGENTS](../schema/AGENTS.md)
* [`Lux::Type` AGENTS](../type/AGENTS.md)
* [`Lux::Policy` AGENTS](../policy/AGENTS.md)
