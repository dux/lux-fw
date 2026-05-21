# Lux::Cache - agent guide

Cache with one API across backends.

## Canonical example

```ruby
# in initializer
Lux::Cache.server = :memcached            # or :memory, :sqlite, :null, Dalli::Client.new(...)

# anywhere
Lux.cache.fetch('users/count', ttl: 60) { User.count }
Lux.cache.fetch_if_true('session', ttl: 60) { user.still_valid? }
Lux.cache.lock('task', 3) { do_it }       # process-local rate limit
Lux.cache.delete('users/count')

key = Lux.cache.generate_key(User, Product.find(3), 'data')
Lux.cache.fetch(key, ttl: 60) { ... }

# array keys are auto-serialized and stable across calls
User.current.cache([Date.today, :my_daily]) { compute_daily }
```

## Rules

* **One API across backends.** Don't write backend-specific code in
  consumers - swap servers via `Lux::Cache.server =`.
* **`fetch` is the workhorse.** Prefer it to manual read+write pairs.
* **`fetch_if_true`** caches only truthy results - the right pattern for
  "valid?" / "allowed?" checks where false should be re-evaluated.
* **`lock(key, secs)`** is process-local cooperative rate limiting,
  **NOT** a cross-process mutex. Don't use for "only one worker"
  coordination - use Postgres advisory locks for that.
* **Cache keys can be arrays.** `Lux.cache.fetch([scope, id], ttl: 60)`
  is fine; the backend serializes. Avoids string interpolation noise
  when keys are composite.
* **Key generation:** `Lux.cache.generate_key(*args)` builds a stable
  key from anything responding to `:id`, `:updated_at`, `:created_at`.
* **For request-scoped memoization**, use `current.cache(key) { ... }`
  ([`Lux::Current`](../current/AGENTS.md)) - not `Lux.cache`.

## Don't

* Cache user-specific data with a public key. Always include `user.id`
  / `user.updated_at` in the key.
* Use `:memcached` without setting a namespace - keys will collide
  across apps on the same server.
* Cache values that fail to serialize (Proc, IO). Backends raise.
* Treat `:memory` as durable - it's per-process; restarts wipe.

## See also

* [`Lux::Current` AGENTS](../current/AGENTS.md) - `current.cache` (request-scope)
