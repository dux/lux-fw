## Lux.current.response (Lux::Response)

Current request response object.

You can always use `Lux.current.response`, or access it as `response` inside a controller.

```ruby
# add response header
response.header 'x-blah', 123

# page status
response.status = 400
```

### Cache control

Default cache is **private** and uncached. You do not need to call anything for the default.

```ruby
# Cache-Control: private, must-revalidate, max-age=0
```

Public (shared) cache is opt-in:

```ruby
response.cache.public  = true
response.cache.max_age = 10.minutes
response.cache.stale_while_revalidate = 1.hour
```

Shortcut for the common case:

```ruby
response.cache_public 10.minutes
```

Disable caching and cookies for sensitive responses:

```ruby
response.no_store
```

ETags:

```ruby
response.etag :users, User.max(:updated_at)
```

Important rules:

* Private cache is default.
* Public cache never emits `Set-Cookie`.
* Flash forces the response private.
* `response.no_store` suppresses both the cache and the session cookie.
* `response.max_age = N` is kept as a back-compat alias; setting positive max-age implies public cache.

### Body

```ruby
response.body = 'hello'    # set
response.body              # get
response.body?             # true if body present
```

### Content type

```ruby
response.content_type = :js
response.content_type = :plain
response.content_type
```

### Flash

```ruby
response.flash 'Bad user name or pass'
response.flash.error 'Bad user name or pass'
response.flash.info 'Login ok'
```

### File / redirect / auth

```ruby
# send file to a browser
response.send_file './tmp/local/location.pdf', inline: true

# redirect the request
response.redirect_to '/foo'
response.redirect_to :back, error: 'Bad user name or pass'

# halt response render and deliver page
response.halt status, body

# HTTP early hints
response.early_hints link, type

# basic http auth
response.auth do |user, pass|
  [user, pass] == ['foo', 'bar']
end
```
