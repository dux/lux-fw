## Lux.current (Lux::Current)

Lux handles state of the app in the single object, stored in `Thread.current`, available everywhere.

You are not forced to use this object, but you can if you want to.

```ruby
current.session         # session, encoded in cookie
current.locale          # locale, default nil
current.request         # Rack request
current.response        # Lux response object
current.nav             # lux nav object
current.cookies         # Rack cookies
current.can_clear_cache # set to true if user can force refresh cache
current.var             # CleaHash to store global variables
current[:user]          # current.var.user
current.uid             # new unique ID in a page, per response
current.secure_token    # Get or check current session secure token

# Execute only once in current scope
current.once { @data }
current.once(key, @data)

# Cache in current response scope
current.cache(key) {}

# Set current.can_clear_cache = true if user is able to clear cache with SHIFT+refresh
current.no_cache?              # false
current.can_clear_cache = true
current.no_cache?              # true if env['HTTP_CACHE_CONTROL'] == 'no-cache'


```
