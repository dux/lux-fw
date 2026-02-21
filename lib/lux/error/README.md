## Lux.error (Lux::Error)

Error handling module.

### HTTP Error Helpers

```ruby
# 400: for bad parameter request
Lux.error.bad_request message

# 401: for unauthorized access
Lux.error.unauthorized message

# 403: for forbidden access
Lux.error.forbidden message

# 404: for not found pages
Lux.error.not_found message

# 500: for internal server error
Lux.error.internal_server_error message
```

### Rendering

```ruby
# HTML render style for default Lux error
Lux::Error.render(error)

# Show inline error
Lux::Error.inline(error, message)
```
