# Lux::Error

Thin exception class. HTTP status is set on the response, not carried
on the exception. `Lux.error` returns a proxy with named helpers that
raise with the right status.

## Full example

```ruby
# --- raise helpers (set response status, then raise Lux::Error) ----------

Lux.error.bad_request 'name missing'             # 400
Lux.error.unauthorized 'login required'          # 401
Lux.error.payment_required 'upgrade'             # 402
Lux.error.forbidden 'no access'                  # 403
Lux.error.not_found 'no such user'               # 404
Lux.error.method_not_allowed 'POST only'         # 405
Lux.error.not_acceptable                         # 406
Lux.error.internal_server_error 'boom'           # 500
Lux.error.not_implemented                        # 501

# --- arbitrary status / generic ------------------------------------------

Lux.error 404                                    # status 404, default message
Lux.error 418, "I'm a teapot"                    # status + custom message
Lux.error 'generic'                              # status 400, custom message

# --- in-controller use ---------------------------------------------------

def show
  @user = User.find(nav.ref) or Lux.error.not_found
  Lux.error.forbidden unless @user.can.read?
end

# --- conditional rendering across dev / prod -----------------------------

# dev: include the detailed message; prod: bare 404
Lux.error.not_found Lux.mode.debug?('404 Not Found') {
  'Subdomain "%s" matched but nothing called' % name
}

# --- override controller :error to customise rescue ---------------------

class ApplicationController < Lux::Controller
  def error
    Lux.logger.error @error.message
    if @status == 404
      render :not_found
    else
      render :server_error
    end
  end
end

# --- direct render helpers (used by the framework's fallback) ------------

Lux::Error.render(exception)         # full HTML/JSON error page
Lux::Error.inline(exception)         # inline panel (for embeds)
Lux::Error.format(exception, html: true, gems: false, message: true)
```

## Resolution order on raise

1. `Lux.app rescue_from { |err| ... }` if defined (router-level)
2. The active controller's `:error` action
3. `Lux::Error.render` (framework default)

The active controller's `:error` action receives `@error` (exception)
and `@status` (resolved HTTP code) as instance variables.

## See also

* [`../application/README.md`](../application/README.md) - `rescue_from`
* [`../controller/README.md`](../controller/README.md) - default `:error` action + `rescue_from` macro
