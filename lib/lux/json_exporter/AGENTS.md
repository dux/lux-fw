# Lux::JsonExporter - agent guide

Structured JSON export. One exporter class per model, multiple "shapes".

## Canonical example

```ruby
class UserExporter < Lux::JsonExporter
  define do
    json[:ref]   = model.ref
    json[:name]  = model.name
    json[:email] = model.email if opts[:admin]
  end

  define :card do
    json[:ref]    = model.ref
    json[:avatar] = model.avatar_url
  end

  before { json[:exported_at] = Time.now.iso8601 }
  after  { json.compact! }
end

UserExporter.export(@user)
UserExporter.export(@user, shape: :card, admin: true)
UserExporter.export(User.all)            # array passthrough
```

## Rules

* **One exporter per model.** Name as `<Model>Exporter`. Place in
  `app/exporters/`.
* **`define` registers** under the exporter class name. `define :shape`
  registers a named variant; pass `shape:` to `.export` to select.
* **`model`, `opts`, `json`** are available inside `define` / `before` /
  `after` blocks.
* **Arrays work** - pass `User.all`, get back an array of hashes.
* **`before` / `after`** run around every export call. Use for common
  metadata or compaction.
* **Compose**: an exporter can call another exporter
  (`OrgExporter.export(model.org)`) to embed.

## Don't

* Inline JSON-building in controllers / APIs - hoist to an exporter so
  shapes are consistent and discoverable.
* Mutate `model` inside the exporter. Read-only.
* Stuff response shaping logic into the model. The model is the model;
  the exporter is the API shape.

## See also

* [`Lux::Api` AGENTS](../api/AGENTS.md) - typical caller
