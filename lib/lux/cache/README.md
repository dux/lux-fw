# Lux::Cache

Cache with a uniform API across backends (memory, memcached, sqlite, null).
Pick a backend - the methods are the same.

`Lux.cache` returns the shared cache server; `Lux.cache(:key) { ... }` is a
process-local memoize (no TTL, no clear) backed by `Lux.var`.

## Full example

```ruby
# --- pick a backend (typically in ./config/initializers/cache.rb) -------

Lux.cache.server                    # current backend; default :memory
Lux.cache.server = :memcached       # uses MEMCACHE_SERVERS / Dalli
Lux.cache.server = :sqlite          # ./tmp/lux_cache.sqlite (WAL)
Lux.cache.server = :null            # no-op (tests)
Lux.cache.server = Dalli::Client.new('localhost:11211', namespace: 'app', expires_in: 1.hour)

# --- read / write -------------------------------------------------------

Lux.cache.write('key', value, 60)    # ttl seconds
Lux.cache.read('key')                 # alias: get
Lux.cache.read_multi('a', 'b', 'c')  # alias: get_multi
Lux.cache.delete('key')

# --- fetch (the workhorse) ---------------------------------------------

Lux.cache.fetch('users/count', ttl: 60) { User.count }

# fetch options:
#   ttl:               seconds before expiry
#   force: true        bypass and recompute
#   if: false          skip cache, just yield
#   delete_if_empty:   drop entry if block returns empty?

# only cache truthy results (auth pattern)
Lux.cache.fetch_if_true('session/check', ttl: 60) { user.still_valid? }

# --- key generation -----------------------------------------------------

# objects contribute class + `id` + `updated_at` (else `to_s`); the values
# get joined into a stable key
key = Lux.cache.generate_key(caller.first, User, Product.find(3), 'data')
Lux.cache.fetch(key, ttl: 60) { ... }

# --- cooperative rate limit (NOT a mutex) -------------------------------

Lux.cache.lock('expensive-task', 3) { do_it }
# a caller within 3s of the last run sleeps out the remainder, then runs the block

# --- inspect ------------------------------------------------------------

Lux.cache.is_available?              # backend reachable?
Lux.cache.server                     # current backend

# --- process-local memoize (no TTL, no clear) ---------------------------

Lux.cache(:boot_config) { JSON.parse(File.read('config.json')) }
# subsequent calls in this process return the cached value verbatim.
# Backed by Lux.var (a process-local hash); use it for "compute once
# per boot" data that doesn't belong on a cache server.

Lux.var                              # the underlying Hash if you need direct access
```

## Backends

| Backend | Notes |
|---------|-------|
| `:memory` (default) | per-process RAM, TTL-aware, periodic sweep, LRU-capped at `MemoryServer::MAX_KEYS` (10k) |
| `:memcached`       | via Dalli (needs `dalli` in the app Gemfile). `MEMCACHE_SERVERS`, `MEMCACHE_NAMESPACE` |
| `:sqlite`          | file-backed, WAL mode, survives restarts (needs `sqlite3` in the app Gemfile) |
| `:null`            | no-op; use in tests |
| custom             | any object answering `get`/`set`/`delete`/`fetch`/`get_multi`/`clear` |

## See also

* [`../context/README.md`](../context/README.md) - `Lux.ctx.cache` for request-scoped caching
