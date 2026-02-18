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

### Exception Logging

Real exceptions (not `Lux::Error`) are automatically logged to `./log/exception.log`.

```ruby
# Log an exception (skips Lux::Error instances)
Lux::Error.log(error_object)

# Define custom error handler (for DB, Sentry, etc.)
Lux::Error.on_error do |error|
  # Log to database
  ExceptionLog.create(
    error_class: error.class.to_s,
    message: error.message,
    backtrace: error.backtrace&.join("\n")
  )

  # Or send to Sentry
  Sentry.capture_exception(error)
end
```

### Rendering

```ruby
# HTML render style for default Lux error
Lux::Error.render(error)

# Show inline error
Lux::Error.inline(error, message)
```
