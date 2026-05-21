# Lux::Hash

Hash with indifferent access (strings and symbols are the same key).
Used everywhere the framework returns or accepts a hash that needs
flexible key access.

## Small example

```ruby
h = { 'name' => 'Dux' }.to_lux_hash
h[:name]                 # 'Dux'
h['name']                # 'Dux'
h.name                   # 'Dux' (method-style access)
```

## Full example

```ruby
# build
h = Lux::Hash.new
h = Lux::Hash.new(name: 'Dux', email: 'd@x.com')
h = { 'a' => 1 }.to_lux_hash

# access (all equivalent)
h[:name]
h['name']
h.name

# nested access
h[:user][:profile][:age]
h.dig(:user, :profile, :age)

# named-option helper (builds a struct-like)
opts = Lux::Hash(arg1, arg2, defaults: {limit: 10})
opts.limit
```

## NOTE for code inside `module Lux`

Inside the `Lux` namespace, the bare identifier `Hash` resolves to
`Lux::Hash`, NOT `::Hash`. This causes subtle bugs in `case` statements
and `is_a?` checks. Use predicates from `lib/overload/object.rb`:

```ruby
# bad - never matches plain Ruby hashes
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

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`lib/overload/object.rb`](../../overload/object.rb) - `is_hash?` + siblings
