# Lux::Schema

The schema DSL at the heart of the framework. The same line parser drives
controller params, API params, model field definitions, and standalone
validation/coercion.

`Lux.schema(name) { ... }` defines and stores a schema by name;
`Lux.schema(name)` looks it up (raises if missing); `Lux.schema?(name)`
returns nil if missing.

## Full example

```ruby
# --- inline (one-off, no store) ----------------------------------------

schema = Lux.schema do
  name  String, max: 30
  email type: :email
  age   Integer, req: false
end

errors = schema.validate({ 'name' => 'Dux', 'email' => 'foo@bar.baz' })
# errors == {} ; hash is now coerced + filtered in place

# --- named (stored under SCHEMA_STORE; lookup with Lux.schema(:user)) -

Lux.schema :user do
  name     String, max: 30
  email    type: :email, index: true
  bio?     String                                  # `?` suffix = optional
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

# --- line forms (all equivalent) --------------------------------------

# inside a `schema do ... end` block:
name String, max: 30                  # method-missing -> set
set :name, type: String, max: 30      # explicit
name? String, max: 30                 # optional

# above a controller / API def:
opt :name, String, max: 30            # same parser, method-level form

# --- lookup / introspect ----------------------------------------------

Lux.schema(:user)                     # raises if missing
Lux.schema?(:user)                    # nil if missing
Lux.schema(type: :model)              # find all schemas matching an opt (returns class names)
Lux.schema(:user).rules               # { name: { type: :string, ... }, ... }
Lux.schema(:user).db_schema           # [[field, db_type, db_opts], ...]
Lux.db_schema(:user)                  # shortcut

# --- subset / superset -------------------------------------------------

Lux.schema(:user).only(:name, :email)        # new Schema with those two
Lux.schema(:user).except(:age, :country)     # new Schema without those

# --- validate ----------------------------------------------------------

data = { 'name' => 'Dux', 'email' => 'd@x.com', 'role' => 'admin', 'age' => '42' }
errors = Lux.schema(:user).validate(data)
# errors == {} ; data is now { 'name' => 'Dux', email: ..., role: 'admin', age: 42 (coerced), ... }

# Strict mode (default for controllers/APIs): also DROPS undeclared keys
Lux.schema(:user).validate(data, strict: true)

# Block form yields (field, message) for each error and returns nil
Lux.schema(:user).validate(data) do |field, msg|
  puts "#{field}: #{msg}"
end

Lux.schema(:user).valid?(data)        # true / false
```

## Option keys (recognised by every type)

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

## Validation behaviour

* `schema.validate(hash)` mutates the hash in place: coerced values
  replace raw input, blank empty strings become `nil`.
* Pass `strict: true` to also drop undeclared keys (controllers and APIs
  do this by default when any opts are declared).
* Block form yields `(field, message)` for each error; otherwise returns
  the errors hash.
* `schema.valid?(hash)` returns `true`/`false`.

## See also

* [`../type/README.md`](../type/README.md) - the named-type vocabulary
* [`../controller/README.md`](../controller/README.md) - `opt` / `params do`
* [`../api/README.md`](../api/README.md) - same DSL for API endpoints
