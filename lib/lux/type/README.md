# Lux::Type

Named types - the type vocabulary the rest of the framework uses. Each
type defines its own coercion, validation, and DB column shape. The same
type works in a controller `opt`, an API `params do`, a schema, or a
migration.

`Lux.type(name)` returns the type class; `Lux.type(name, value)` coerces
a value through the type (raising on failure, or yielding to a block).

## Full example

```ruby
# --- look up / coerce ---------------------------------------------------

Lux.type(:email)                         # => Lux::Type::EmailType class
Lux.type(:email, 'd@x.com')              # => 'd@x.com' (lowercased, validated)
Lux.type(:email, 'not-an-email')         # raises TypeError

Lux.type(:integer, '42')                 # => 42
Lux.type(:slug, 'My Title!')             # => 'my-title'

# Block form: yields the TypeError instead of raising; coerce returns false
Lux.type(:email, 'bad') { |err| flash.error err.message }

# --- usage in a schema / opt block --------------------------------------

opt :email,   type: :email
opt :country, type: :country
opt :id,      type: :uuid

Lux.schema :user do
  email   type: :email
  country type: :country, default: 'HR'
end
```

## Built-in types

Located in [`lib/lux/type/types/`](./types).

| Symbol | Coerces to | Notes |
|--------|------------|-------|
| `:string`    | String  | default when no type given |
| `:text`      | String  | unlimited length, multi-line |
| `:integer`   | Integer | `min:`, `max:` |
| `:float`     | Float   | `min:`, `max:` |
| `:boolean`   | true/false | `"on"`, `"1"`, `"true"` → true |
| `:date`      | Date    | ISO parse |
| `:datetime`  | DateTime | ISO parse |
| `:time`      | Time    | |
| `:email`     | String  | validates RFC + lowercases |
| `:url`       | String  | validates http/https |
| `:slug`      | String  | URL-safe slug |
| `:uuid`      | String  | RFC-4122 |
| `:locale`    | String  | two-letter, lowercased |
| `:country`   | String  | ISO 3166-1 alpha-2, uppercased |
| `:currency`  | Float   | `to_f.round(2)` |
| `:currency_code` | String | ISO 4217, uppercased |
| `:phone`     | String  | strips parens/dashes, requires 5+ digits |
| `:iban`      | String  | validates IBAN |
| `:oib`       | String  | Croatian tax id |
| `:label`     | String  | enum-friendly |
| `:point` / `:simple_point` | Array(Float, Float) | lat/lon |
| `:hash`      | Hash    | passes through |
| `:translated` | Hash(locale => text) | jsonb; bare string → current locale; prunes stale locales when a single one changes |
| `:image`     | upload  | works with `plugins/web_common` html form |
| `:model`     | nested schema | set automatically by `name do ... end` |

## Defining a custom type

```ruby
# lib/lux/type/types/positive_integer_type.rb
module Lux
  class Type
    class PositiveIntegerType < Type
      # declare any type-specific opts so Schema accepts them
      opts :allow_zero, 'permit 0 as a valid value'

      def coerce
        @value = @value.to_i
        error_for(:min_value_error, opts[:allow_zero] ? 0 : 1, @value) if @value < (opts[:allow_zero] ? 0 : 1)
      end

      def db_schema
        [:integer, {}]
      end
    end
  end
end

# Use anywhere:
opt :age, type: :positive_integer, allow_zero: true
```

Inside `coerce`, a type also sees `stored_value` - the value currently persisted for
that field (from the Sequel `:dirty` baseline). It is `nil` for new rows, param-hash
validation and nested schemas. Types that need to merge or prune against prior state
(e.g. `:translated`) compare the incoming value to `stored_value`.

## Translations

```ruby
# default English errors live in Lux::Type::ERRORS[:en]
Lux::Type.error :hr, :min_length_error, 'minimalna duljina je %s, imate %s'
Lux::Type.error :hr, :max_length_error, 'maksimalna duljina je %s, imate %s'

# resolves via Lux.current.locale automatically when validating
```

Per-field overrides via `meta:` option:

```ruby
opt :name, String, max: 30, meta: { max_length_error: 'too long, max 30' }
opt :name, String, max: 30, meta: { hr: { max_length_error: 'predugo' } }
```

## See also

* [`../schema/README.md`](../schema/README.md) - the DSL that consumes types
