# Lux::Cache

Cache with a uniform API across backends (memory, memcached, sqlite, null).
Pick a backend - the methods are the same.

## Small example

```ruby
Lux.cache.fetch('users/count', ttl: 60) { User.count }
```

## Full example

```ruby
# --- pick a backend (in ./config/initializers/cache.rb) -----------------

Lux::Cache.server                     # default :memory
Lux::Cache.server = :memcached        # uses MEMCACHE_SERVERS / Dalli
Lux::Cache.server = :sqlite           # ./tmp/lux_cache.sqlite (WAL)
Lux::Cache.server = :null             # no-op (tests)
Lux::Cache.server = Dalli::Client.new('localhost:11211', namespace: 'app', expires_in: 1.hour)

# --- read / write -------------------------------------------------------

Lux.cache.write('key', value, 60)     # ttl seconds
Lux.cache.read('key')                  # alias: get
Lux.cache.read_multi('a', 'b', 'c')   # alias: get_multi
Lux.cache.delete('key')

# --- fetch (the workhorse) ---------------------------------------------

Lux.cache.fetch('users/count', ttl: 60) { User.count }

# fetch options:
#   ttl:               seconds before expiry
#   force: true        bypass and recompute
#   if: false          skip cache, just yield
#   delete_if_empty:   drop entry if block returns empty?
#   speed:             filled in with the compute time

# only cache truthy results (auth pattern)
Lux.cache.fetch_if_true('session/check', ttl: 60) { user.still_valid? }

# --- key generation -----------------------------------------------------

# accepts anything responding to :id, :updated_at, :created_at; the values
# get appended to make a stable key
key = Lux.cache.generate_key(caller.first, User, Product.find(3), 'data')
Lux.cache.fetch(key, ttl: 60) { ... }

# --- process-local rate limit (NOT a cross-process mutex) ---------------

Lux.cache.lock('expensive-task', 3) { do_it }
# subsequent callers in the SAME process within 3s skip the block

# --- inspect ------------------------------------------------------------

Lux.cache.is_available?               # backend reachable?
Lux.cache.server                      # current backend
```

## Backends

| Backend | Notes |
|---------|-------|
| `:memory` (default) | per-process RAM, TTL-aware, periodic sweep |
| `:memcached`       | via Dalli. `MEMCACHE_SERVERS`, `MEMCACHE_NAMESPACE` |
| `:sqlite`          | file-backed, WAL mode, survives restarts |
| `:null`            | no-op; use in tests |
| custom             | any object answering `read`/`write`/`delete`/`exist?` |

## See also

* [`../current/README.md`](../current/README.md) - `current.cache` for request-scoped caching
* [`AGENTS.md`](./AGENTS.md) - LLM guide
