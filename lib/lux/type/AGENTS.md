# Lux::Type - agent guide

Named types. Each is a class under `lib/lux/type/types/`, looked up via
`Lux::Type.load(:name)` which classifies `:name` to `Lux::Type::NameType`.

## Canonical example: adding a new type

```ruby
# lib/lux/type/types/positive_integer_type.rb
module Lux
  class Type
    class PositiveIntegerType < Type
      opts :allow_zero, 'permit 0 as a valid value'

      def coerce
        @value = @value.to_i
        floor  = opts[:allow_zero] ? 0 : 1
        error_for(:min_value_error, floor, @value) if @value < floor
      end

      def db_schema
        [:integer, {}]
      end
    end
  end
end
```

Then anywhere:

```ruby
opt :age, type: :positive_integer, allow_zero: true
```

## Rules

* Subclass `Lux::Type`. Naming is mandatory: `Lux::Type::FooBarType` is
  loaded by `Lux::Type.load(:foo_bar)`.
* Implement `coerce` (mutates `@value`) and `db_schema` (returns
  `[:column_type, {opts}]`).
* For new opt keys, declare them with `opts :key, 'description'` so
  `Lux::Schema::Define` accepts them. Otherwise validation will reject the
  key as "unallowed param". Declared opts inherit down the class chain -
  a subclass does not need to redeclare keys from its parent.
* For min/max validation, prefer the shared helpers on the base class:
  `check_min_max` (numeric/comparable) and
  `check_min_max_length(max_default = nil, min_default = nil)` (length).
  Both read `opts[:min]` / `opts[:max]` and raise the standard error keys.
* Raise `TypeError` via `error_for(:key, *args)` so the message is
  locale-aware (defined in `Lux::Type::ERRORS[locale][key]`).
* Built-in error keys: `:min_length_error`, `:max_length_error`,
  `:min_value_error`, `:max_value_error`, `:unallowed_characters_error`,
  `:not_in_range`. Add more via `Lux::Type.error :en, :my_key, '...'`.
* If your type needs a special DB representation (array, jsonb, geometry),
  return that in `db_schema` - migrations pick it up.

## Don't

* Define types as plain procs inside schema blocks. Promote to a class
  under `types/` so all subsystems share it.
* Hardcode user-facing strings - go through `error_for` so translations work.
* Override `default` unless your type has a non-nil sensible default.

## Where it's wired

* `Lux::Schema::Define#validate_opts` calls `Lux::Type.load(type).allowed_opt?(key)`
  for every option key, so unknown opt keys raise at schema-definition time.
* `Lux::Schema#validate` calls `Lux::Type.load(opts[:type]).new(value, opts).db_value`
  to coerce each scalar field.
* DB migrations (in `plugins/db`) call `type.db_schema` to map to a column type.
