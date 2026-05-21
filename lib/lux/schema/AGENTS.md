# Lux::Schema - agent guide

The framework's shared schema DSL. **Reuse this everywhere a list of fields
needs validation, coercion, or db-schema generation. Do not invent
per-subsystem validators.**

## Canonical example

```ruby
Lux.schema :user do
  name       String, max: 30
  email      type: :email, index: true
  bio?       String                          # `?` suffix == optional
  role       %w[admin user guest]            # enum
  age        Integer, min: 13, max: 130
  signed?    type: :boolean
  tags?      [String]                        # array of strings

  # default-value shorthand: a bare literal sets type + default
  is_active  true                            # boolean, default true
  is_deleted false                           # boolean, default false
  count      Integer, default: 0

  # meta: UI hints consumed by the form builder / API explorer
  status     max: 20, meta: { as: :buttons, collection: %w[draft live archived] }
  logo?      :url,   meta: { as: :image, label: 'Square logo' }
  notes?     :text,  meta: { hint: 'Markdown supported', placeholder: '...' }

  address  do                                # nested schema
    street String
    city   String
  end
end

errors = Lux.schema(:user).validate(params, strict: true)
# - mutates params (coerces values, drops blanks)
# - with strict: true, drops keys not declared
# - returns {} or { field: 'msg', ... }
```

## Rules to follow

* **Line parser** is in `lib/lux/schema/define.rb`. Three equivalent forms
  produce the same rule:
  * `name String, max: 30` (shortcut via `method_missing`)
  * `set :name, type: String, max: 30` (explicit)
  * `opt :name, String, max: 30` (the above-method controller form)
* **Field-name suffix `?`** marks the field optional. Default required.
* **Type vocabulary**: any built-in class (`String`, `Integer`, ...) or
  symbol resolving to a `Lux::Type` (`:email`, `:url`, `:uuid`, `:slug`,
  `:locale`, ...). See [`../type/AGENTS.md`](../type/AGENTS.md) to add new
  types - **do not** add inline validation lambdas; promote to a type.
* **Block form** (`address do ... end`) creates a nested schema with
  `type: :model`.
* **Named schemas** (`Lux.schema(:user) { ... }`) are stored in
  `Lux::Schema::SCHEMA_STORE` and re-fetched via `Lux.schema(:user)`. Use
  named schemas for anything referenced by more than one caller.
* `schema.only(:a, :b)` / `schema.except(:a)` build derived schemas without
  duplicating field declarations.
* **`meta:` hash** carries non-validation metadata used by downstream
  consumers (form builders, API explorer, generators). Common keys
  observed in real apps: `as:` (`:image`, `:buttons`, `:checkbox`,
  `:textarea`), `label:`, `hint:`, `placeholder:`, `collection:`
  (enum-like values for picklists, can be a lambda).
* **Literal-default shorthand:** `field true` / `field false` /
  `field 0` is equivalent to `field type: :boolean, default: true` /
  `field type: :integer, default: 0`. Use for simple boolean and
  numeric defaults that read as documentation.

## Don't

* Build your own validator class. The framework already wires `validate`
  + coercion + strict-key-filter; use it.
* Use `:type => SomeRubyClass` as a fancy proc - if it's a custom rule,
  add a `Lux::Type` subclass under `lib/lux/type/types/`.
* Forget `strict: true` when validating user input from HTTP - the default
  is non-strict (keeps undeclared keys) which is the wrong default for
  request bodies.

## Where it's wired

| Caller | How |
|--------|-----|
| `Lux::Controller#opt` / `Lux::Controller.params` | builds a Schema via `Lux.schema(&block)`, validates with `strict: true` |
| `Lux::Api.params`        | same |
| Model `schema do ... end` (plugins/db) | builds + stores under model name, drives DB schema and validation |
| Manual                   | `Lux.schema(&block).validate(hash, strict: true)` |
