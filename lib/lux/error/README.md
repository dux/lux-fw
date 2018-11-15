## Lux::Errors - In case of error

### module Lux::Error

```ruby
  # try to execute part of the code, log exeception if fails
  def try(name, &block)

  # HTML render style for default Lux error
  def render(desc)

  # show error page
  def show(desc)

  # show inline error
  def inline(name=nil, o=nil)

  # log exeption
  def log(exp_object)
```


### defines standard Lux errors and erro generating helpers

```ruby
# 400: for bad parameter request or similar
Lux::Error.forbidden foo

# 401: for unauthorized access
Lux::Error.forbidden foo

# 403: for unalloed access
Lux::Error.forbidden foo

# 404: for not found pages
Lux::Error.not_found foo

# 503: for too many requests at the same time
Lux::Error.forbidden foo

```
