# Lux::JsonExporter

Structured JSON export from any object. Define named exporters once,
reuse anywhere. Common pattern: one exporter per model, multiple
"shapes" (list / show / nested).

## Small example

```ruby
class UserExporter < Lux::JsonExporter
  define do
    json[:ref]  = model.ref
    json[:name] = model.name
  end
end

UserExporter.export(@user)
# => { ref: '...', name: '...' }
```

## Full example

```ruby
class UserExporter < Lux::JsonExporter
  # default exporter
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
    json[:ref]  = model.ref
    json[:org]  = OrgExporter.export(model.org)
  end

  # filters
  before { json[:exported_at] = Time.now.iso8601 }
  after  { json.compact! }
end

# --- usage -----------------------------------------------------------

UserExporter.export(@user)
UserExporter.export(@user, admin: true)
UserExporter.export(@user, shape: :card)
UserExporter.export(@users)              # accepts arrays

# from an API endpoint
class UsersApi < ApplicationApi
  desc 'List users'
  define :list do
    proc { UserExporter.export(User.all) }
  end
end
```

## DSL

```ruby
define do ... end              # default exporter
define :shape do ... end       # named exporter
before do ... end              # runs before block
after  do ... end              # runs after block

# inside a block:
model                          # the object being exported
opts                           # options passed to .export
json                           # the hash being built
```

## See also

* [`../api/README.md`](../api/README.md) - APIs often return exported objects
* [`AGENTS.md`](./AGENTS.md) - LLM guide
