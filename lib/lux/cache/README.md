## Lux.cache (Lux::Cache)

Simplifed caching interface, similar to Rails.

Should be configured in `./config/initializers/cache.rb`

```ruby
# init
Lux::Cache.server # defauls to memory
Lux::Cache.server = :memcached
Lux::Cache.server = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })

# read cache
Lux.cache.read key
Lux.cache.get key   # alias

# multi read (keys are passed through to the backend as-is)
Lux.cache.read_multi(*args)
Lux.cache.get_multi(*args)   # alias

# write
Lux.cache.write(key, data, ttl=nil)
Lux.cache.set(key, data, ttl=nil)   # alias

# delete
Lux.cache.delete(key)

# fetch or set
Lux.cache.fetch(key, ttl: 60) do
  # ...
end

# fetch options:
#   ttl: Integer            - expire after N seconds
#   force: true             - bypass cache, recompute and store
#   if: false               - skip caching entirely, just yield
#   delete_if_empty: true   - if computed value is empty?, drop from cache
#   speed                   - filled by the cache with the compute time

# fetch only if block returns truthy (security-check pattern)
Lux.cache.fetch_if_true(key, ttl: 60) { ... }

# process-local cooperative rate limit (NOT a cross-process mutex)
Lux.cache.lock('some-key', 3) { ... }

Lux.cache.is_available?

# Generate cache key
# You can put anything in args and if it responds to :id, :updated_at, :created_at
# those values will be added to keys list
Lux.cache.generate_key *args
Lux.cache.generate_key(caller.first, User, Product.find(3), 'data')
```

### Backends

* `:memory`    -- per-process in-RAM, TTL-aware, periodic sweep.
* `:memcached` -- via Dalli. Honors `MEMCACHE_SERVERS`; namespace from
  `MEMCACHE_NAMESPACE` or hash of `Lux.root`.
* `:sqlite`    -- file-backed (`./tmp/lux_cache.sqlite` by default); WAL mode.
* `:null`      -- no-op; useful for tests.
