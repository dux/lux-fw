# Lux::Type

Named types - the type vocabulary the rest of the framework uses. Each
type defines its own coercion, validation, and DB column shape. The same
type works in a controller `opt`, an API `params do`, a schema, or a
migration.

## Small example

```ruby
# anywhere you can name a type:
opt :email,   type: :email
opt :country, type: :country
opt :id,      type: :uuid

# direct use:
Lux::Type.load(:email).new('foo@bar.baz').get
# => 'foo@bar.baz'  (or raises TypeError with message)
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
| `:currency`  | Float   | parsed with locale |
| `:currency_code` | String | ISO 4217, uppercased |
| `:phone`     | String  | E.164 normalize |
| `:iban`      | String  | validates IBAN |
| `:oib`       | String  | Croatian tax id |
| `:label`     | String  | enum-friendly |
| `:point` / `:simple_point` | Array(Float, Float) | lat/lon |
| `:hash`      | Hash    | passes through |
| `:image`     | upload  | works with `plugins/html` form |
| `:model`     | nested schema | set automatically by `name do ... end` |

## Full example: defining a custom type

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
```

Now usable anywhere:

```ruby
opt :age, type: :positive_integer, allow_zero: true
```

## Translations

```ruby
# default English errors live in Lux::Type::ERRORS[:en]
# add your own locale:
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

* [`Lux::Schema` README](../schema/README.md) - the DSL that consumes types
* [`AGENTS.md`](./AGENTS.md) - LLM guide for adding new types
