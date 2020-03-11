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
Lux.cache.get key

# multi read
Lux.cache.read_multi(*args)
Lux.cache.get_multi(*args)

# write
Lux.cache.write(key, data, ttl=nil)
Lux.cache.set(key, data, ttl=nil)

# deelte
Lux.cache.delete(key, data=nil)

# fetch or set
Lux.cache.fetch(key, ttl: 60) do
  # ...
end

Lux.cache.is_available?

# Generate cache key
# You can put anything in args and if it responds to :id, :updated_at, :created_at
# those values will be added to keys list
Lux.cache.generate_key *args
Lux.cache.generate_key(caller.first, User, Product.find(3), 'data')
```
