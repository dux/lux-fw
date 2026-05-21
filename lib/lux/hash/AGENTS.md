# Lux::Hash - agent guide

Hash with indifferent access. The framework's default hash flavor.

## Canonical example

```ruby
h = { 'name' => 'Dux' }.to_lux_hash
h[:name] == h['name']      # true
h.name == h[:name]         # true (method access)

# build
Lux::Hash.new(a: 1, b: 2)

# named-option helper for DSL-style APIs
opts = Lux::Hash(arg1, arg2, defaults: { limit: 10 })
opts.limit
```

## Rules (critical for any code inside `module Lux`)

* **Bare `Hash` inside `module Lux` resolves to `Lux::Hash`,** NOT
  `::Hash`. Plain Ruby hashes do NOT match `when Hash` clauses or
  `obj.is_a?(Hash)` checks inside Lux code. This has caused real bugs.
* **Use predicates** (from `lib/overload/object.rb`):
  * `obj.is_hash?`
  * `obj.is_array?` / `obj.is_string?` / `obj.is_symbol?` / `obj.is_numeric?` / `obj.is_boolean?`
* **Or use `::Hash`** (fully-qualified) when you specifically want Ruby's
  builtin.
* **Strings vs symbols are equivalent keys** in `Lux::Hash` - don't
  normalize manually before storing.
* **Lux::Hash inherits ::Hash**, so `lux_hash.is_a?(::Hash)` is `true`.
  Only the reverse direction is the pitfall.

## Don't

* Write `obj.is_a?(Hash)` inside `module Lux ... end`. Will silently
  break for plain Ruby hashes.
* Force-convert with `.to_h` when you wanted the indifferent access -
  use `.to_lux_hash`.
* Treat `Lux::Hash` as guaranteed-symbolic-keyed - it accepts both, and
  iteration yields whatever the inserter used.

## See also

* [`lib/overload/object.rb`](../../overload/object.rb) - `is_*?` predicates
