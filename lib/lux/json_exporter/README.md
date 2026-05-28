# Lux::JsonExporter

Structured JSON export from any object. Define named exporters once,
reuse anywhere. Common pattern: one exporter per model, multiple
"shapes" (list / show / nested).

## Full example

```ruby
class UserExporter < Lux::JsonExporter
  # default exporter (no name)
  define do
    json[:ref]   = model.ref
    json[:name]  = model.name
    json[:email] = model.email if opts[:admin]
  end

  # named shape (use UserExporter.export(@user, shape: :card))
  define :card do
    json[:ref]    = model.ref
    json[:name]   = model.name
    json[:avatar] = model.avatar_url
  end

  # nested - reuses another exporter
  define :with_org do
    json[:ref] = model.ref
    json[:org] = OrgExporter.export(model.org)
  end

  # filters
  before { json[:exported_at] = Time.now.iso8601 }
  after  { json.compact! }
end

# --- ways to render ---------------------------------------------------

UserExporter.export(@user)                      # default shape
UserExporter.export(@user, admin: true)         # opts visible in block
UserExporter.export(@user, shape: :card)        # named shape
UserExporter.export(@users)                     # accepts arrays / enumerables

# --- shortcut form (Lux.json_exporter) -------------------------------

# Register an exporter for any class (no subclassing):
Lux.json_exporter(Page) do
  json[:ref]   = model.ref
  json[:title] = model.title
end

# Render any object that has a registered exporter:
Lux.json_exporter(Page.first)                   # uses the block registered above
Lux.json_exporter(Page.first, shape: :card)     # named shape (if registered)

# --- in a typical API endpoint ---------------------------------------

class UsersApi < ApplicationApi
  desc 'List users'
  define :list do
    proc { UserExporter.export(User.all) }
  end
end
```

## DSL inside `define`

```ruby
model                          # the object being exported
opts                           # options passed to .export
json                           # the hash being built

prop  :name                    # json[:name] = model.name
property :name, 'value'        # explicit value (alias: prop); block form supported
property(:meta) { |h| h[:a] = 1 }
export :org                    # nested export of an associated object/array
export some_object             # export a passed object (key derived from its class)
merge other_hash               # shallow-merge a hash into json
```

## API

| call | notes |
|------|-------|
| `MyExporter.export(obj, **opts)` | render via the subclass; default + named shapes via `shape:` opt |
| `Lux.json_exporter(Class, &block)` | register an exporter for `Class` (no subclassing needed) |
| `Lux.json_exporter(obj, **opts)` | render `obj` via its registered exporter |

## See also

* [`../api/README.md`](../api/README.md) - APIs often return exported objects
