### Lux.plugin :db

Useful plugins for Jeremy Evans [ruby Sequel gem](https://github.com/jeremyevans/sequel).

#### `on_change`

Dirty-tracking helper available on any `Sequel::Model` instance (requires the `:dirty` plugin).
Yields previous and current values when a column has changed. Does nothing if the column is unchanged.

```ruby
# in a before_save hook or anywhere before the save flushes dirty state
user.name = 'Bob'

user.on_change(:name) do |prev, cur|
  # prev = 'Alice', cur = 'Bob'
  AuditLog.record(:name_changed, from: prev, to: cur)
end
```

Works with any column type — strings, integers, booleans, and PostgreSQL arrays:

```ruby
# Primitive: add (nil -> value), remove (value -> nil), replace (value -> value)
user.on_change(:email) { |prev, cur| ... }  # prev=nil, cur='a@b.c'
user.on_change(:name)  { |prev, cur| ... }  # prev='Alice', cur=nil
user.on_change(:age)   { |prev, cur| ... }  # prev=30, cur=40

# Arrays: element added/removed/replaced, set from empty, cleared
user.on_change(:tags) { |prev, cur| ... }   # prev=['ruby'], cur=['ruby','js']
```

