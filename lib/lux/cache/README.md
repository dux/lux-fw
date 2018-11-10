## Lux::Cache

Alias - `Lux.cache`

### Define

use RAM cache in development, as default

```
Lux::Cache.server = :memcached
```

You can use memcached or redis in production

```
Lux::Cache.server  = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })
```

### Lux::Cache instance methods

Mimics Rails cache methods

```
  Lux.cache.read(key)
  Lux.cache.get(key)

  Lux.cache.read_multi(*args)
  Lux.cache.get_multi(*args)

  Lux.cache.write(key, data, ttl=nil)
  Lux.cache.set(key, data, ttl=nil)

  Lux.cache.delete(key, data=nil)

  Lux.cache.fetch(key, ttl=nil, &block)

  Lux.cache.is_available?
```

Has method to generate cache key

```
  # generates unique cache key based on set of data
  # Lux.cache.generate_key([User, Product.find(3), 'data', @product.updated_at])

  Lux.cache.generate_key(*data)
```