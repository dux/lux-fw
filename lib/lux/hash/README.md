# Lux::Hash

Hash with indifferent access (strings and symbols read the same key,
also via method-style access). Used everywhere the framework returns or
accepts a hash that needs flexible key access.

## Full example

```ruby
# --- build ----------------------------------------------------------

h = Lux::Hash.new
h = Lux::Hash.new(name: 'Dux', email: 'd@x.com')
h = { 'a' => 1 }.to_lux_hash

# --- read / write (all equivalent) ---------------------------------

h[:name]                           # 'Dux'
h['name']                          # 'Dux'
h.name                             # 'Dux'  (method-style)
h.name = 'Other'                   # method-style setter
h[:other] = 1
h.delete(:other)

# --- predicates ----------------------------------------------------

h.foo?                             # truthy unless value is nil / false / 'false' / 0

# --- nested -------------------------------------------------------

h.dig(:user, :profile, :age)       # safe nested read
h.merge(other_hash)                # returns Lux::Hash; coerces nested ::Hash values too
h.merge!(other_hash)
h.clone                            # deep clone via Marshal

# --- named-option DSL (Lux::Hash(...) block form) -----------------
#
# Build a flat enum-style hash with code/label pairs, optionally
# wiring it to a class as a method and/or as constants.

STATUS = Lux::Hash() do |opt|       # plain hash
  opt.ACTIVE   1 => 'Active'
  opt.PENDING  2 => 'Pending'
end
STATUS[1]                          # 'Active'  (code -> value)
STATUS.ACTIVE                      # 'Active'  (named method, NOT a key)
# NOTE: no reverse lookup - STATUS['ACTIVE'] is nil (label is not a key)

# Also expose Foo.status returning the hash:
class Foo
  STATUS = Lux::Hash(self, method: :status) do |opt|
    opt.ACTIVE 1 => 'Active'
  end
end
Foo.status                         # the hash

# Also define Foo::STATUS_ACTIVE = 1 etc:
class Foo
  STATUS = Lux::Hash(self, constants: :status) do |opt|
    opt.ACTIVE 1 => 'Active'
  end
end
Foo::STATUS_ACTIVE                 # 1

# Result is always frozen; there is no opt to keep it mutable.

# --- to_lux_hash structuring ---------------------------------------

# Wrap a plain hash:
{ foo: 1 }.to_lux_hash             # Lux::Hash

# Cast to a dynamic Struct (keys become readers):
{ foo: 1, bar: 2 }.to_lux_hash(:foo, :bar)
```

## A note for code inside `module Lux`

Inside the `Lux` namespace, the bare identifier `Hash` resolves to
`Lux::Hash`, NOT `::Hash`. This causes subtle bugs in `case` statements
and `is_a?` checks. Use predicates from `lib/overload/object.rb`:

```ruby
# bad - never matches plain Ruby hashes when inside module Lux
case route_object
when Hash then ...               # Hash == Lux::Hash here
end

# good - use the predicate
if route_object.is_hash?
  ...
end

# also good - fully qualified
case route_object
when ::Hash then ...
end
```

Same applies to any other `Lux::<CoreClass>` alias (currently only
`Lux::Hash` exists; the rule is forward-compatible).

## See also

* [`lib/overload/object.rb`](../../overload/object.rb) - `is_hash?` + siblings
