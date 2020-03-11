## Lux.error (Lux::Error)

Error handling module.

```ruby
# try to execute part of the code, log exeception if fails
Lux.error.try(name, &block)

# HTML render style for default Lux error
Lux.error.render(desc)

# show error page
Lux.error.show(desc)

# show inline error
Lux.error.inline(name=nil, error_object=nil)

# log exeption via Lux.config.log_exception_via method
Lux.error.log(error_object)
```


#### defines standard Lux errors and error generating helpers

```ruby
# 400: for bad parameter request or similar
Lux.error.forbidden foo

# 401: for unauthorized access
Lux.error.forbidden foo

# 403: for unalloed access
Lux.error.forbidden foo

# 404: for not found pages
Lux.error.not_found foo

# 503: for too many requests at the same time
Lux.error.forbidden foo
```
