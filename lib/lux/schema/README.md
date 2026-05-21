# Lux::Schema

The schema DSL at the heart of the framework. The same line parser drives
controller params, API params, model field definitions, and standalone
validation/coercion.

## Small example

```ruby
schema = Lux.schema do
  name  String, max: 30
  email type: :email
  age   Integer, req: false
end

errors = schema.validate({ 'name' => 'Dux', 'email' => 'foo@bar.baz' })
# => {}  (and the hash is now coerced + filtered)
```

## Line forms

All three lines below produce the same rule:

```ruby
name String, max: 30                  # shortcut: method-missing -> set
set :name, type: String, max: 30      # explicit
name? String, max: 30                 # `?` suffix marks optional
```

Inside a controller / API, `opt :name, String, max: 30` is the above-method
form. Same parser under the hood.

## Full example

```ruby
# Define + store under a name for reuse anywhere via Lux.schema(:user)
Lux.schema :user do
  name     String, max: 30
  email    type: :email, index: true
  bio?     String                                  # optional
  role     %w[admin user guest]                    # enum (allowed values)
  tags?    [String]                                # array of strings
  age      Integer, min: 13, max: 130
  country  type: :country, default: 'HR'
  signed?  type: :boolean

  # nested model
  address  do
    street String
    city   String
  end

  # references another stored schema
  org      type: Lux.schema(:org)
end

# --- validate + coerce ---
data = { 'name' => 'Dux', 'email' => 'd@x.com', 'role' => 'admin', 'age' => '42' }
errors = Lux.schema(:user).validate(data)
# errors == {} ; data == { 'name' => 'Dux', email: ..., role: 'admin', age: 42, ... }

# --- block form yields each error ---
Lux.schema(:user).validate(data) do |field, msg|
  puts "#{field}: #{msg}"
end

# --- subset / superset ---
Lux.schema(:user).only(:name, :email)        # new Schema with two fields
Lux.schema(:user).except(:age, :country)     # new Schema without those

# --- introspect ---
Lux.schema(:user).rules                      # { name: { type: :string, ... }, ... }
Lux.schema(:user).db_schema                  # [[field, db_type, db_opts], ...]
```

## Option keys (recognized by every type)

| Key | Meaning |
|-----|---------|
| `type`         | Type class (`String`, `Integer`, ...) or symbol (`:email`, `:uuid`, ...) |
| `req` / `required` | Required field; default `true` unless `?` suffix |
| `default`      | Default value when input is blank |
| `allow` / `allowed` / `values` | Whitelist of allowed values |
| `array`        | Force-treat as array of `type` |
| `max_count`    | Max array length (default 100) |
| `min_count`    | Min array length |
| `delimiter`    | Array string split regex/string |
| `duplicates`   | Allow duplicates in array |
| `index`        | DB column index hint |
| `desc` / `description` | Human description (used by API explorer) |
| `meta`         | Per-locale custom error messages |

Plus per-type options: `min`, `max` (numbers/strings), and anything declared
on a custom type via `Lux::Type.opts :key, 'desc'`.

## Validation behavior

* `schema.validate(hash)` mutates the hash in place: coerced values
  replace raw input, blank empty strings become `nil`
* Pass `strict: true` to **also drop undeclared keys** (this is what
  controllers and APIs do by default when any opts are declared)
* Block form yields `(field, message)` for each error; otherwise returns
  the errors hash
* `schema.valid?(hash)` returns `true`/`false`

## See also

* [`Lux::Type` README](../type/README.md) - the named-type vocabulary
* [`Lux::Controller` README](../controller/README.md) - `opt` / `params do`
* [`Lux::Api` README](../api/README.md) - same DSL for API endpoints
* [`AGENTS.md`](./AGENTS.md) - LLM guide for adding/using schemas
