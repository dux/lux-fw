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

* **One exporter per model.** Name as `<Model>Exporter`. In real apps
  it usually sits next to the model: `app/models/<model>/<model>_exporter.rb`.
* **`define` registers** under the exporter class name. `define :shape`
  registers a named variant; pass `shape:` to `.export` to select.
* **`model`, `opts`, `json`** are available inside `define` / `before` /
  `after` blocks.
* **Arrays work** - pass `User.all`, get back an array of hashes.
* **`before` / `after`** run around every export call. Use for common
  metadata or compaction.
* **Compose**: an exporter can call another exporter
  (`OrgExporter.export(model.org)`) to embed.

## App-level base class

The framework ships the bones; apps typically **reopen `JsonExporter`**
to add convention helpers shared by every model exporter. The
canonical app-level base looks like:

```ruby
# app/models/json_exporter.rb
class JsonExporter
  def before
    response[:ref]   = model.ref if model.ref
    response[:klass] = model.class.to_s
  end

  def after
    response.transform_values! { |v| v.is_a?(Time) ? v.to_i : v }
  end

  # prop :field -> json[:field] = model.field (and skip nil)
  def prop name, value = :_nil
    value = model.send(name) if value == :_nil
    response[name.to_sym] = value unless value.nil?
  end

  # enum :status -> { name: ..., sid: ... } shape
  def enum name
    value = model.send(name) or return
    response[name.to_sym] = value.is_a?(Hash) ? value : { name: value }
  end
end
```

Subclass exporters then call `prop :name` / `enum :status` instead of
manual `json[:k] = model.k` writes. This pattern is repeated across all
8 real apps - propose it whenever generating new model exporters.

## Don't

* Inline JSON-building in controllers / APIs - hoist to an exporter so
  shapes are consistent and discoverable.
* Mutate `model` inside the exporter. Read-only.
* Stuff response shaping logic into the model. The model is the model;
  the exporter is the API shape.

## See also

* [`Lux::Api` AGENTS](../api/AGENTS.md) - typical caller
