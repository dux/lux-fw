### Lux::Errors

## module Lux::Error

```
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


## defines standard Lux errors and erro generating helpers

```
# 400: for bad parameter request or similar
BadRequestError   ||= Class.new(StandardError)

# 401: for unauthorized access
UnauthorizedError ||= Class.new(StandardError)

# 403: for unalloed access
ForbidenError     ||= Class.new(StandardError)

# 404: for not found pages
NotFoundError     ||= Class.new(StandardError)

# 503: for too many requests at the same time
RateLimitError    ||= Class.new(StandardError)
```
