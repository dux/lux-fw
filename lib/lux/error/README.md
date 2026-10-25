# Lux::Error

Thin exception class that carries its HTTP status (`err.status`, default 400).
`Lux.error` returns a proxy with named helpers that build one with the right status.
Building an error never touches the response; the handler that catches it applies the status, so a rescued `Lux::Error` leaves no trace.

## Full example

```ruby
# --- raise helpers (BUILD the error with its status; you must raise) -------
# Each helper RETURNS a Lux::Error carrying the HTTP status - it does not
# raise on its own. Always `raise` the result.

raise Lux.error.bad_request 'name missing'             # 400
raise Lux.error.unauthorized 'login required'          # 401
raise Lux.error.payment_required 'upgrade'             # 402
raise Lux.error.forbidden 'no access'                  # 403
raise Lux.error.not_found 'no such user'               # 404
raise Lux.error.method_not_allowed 'POST only'         # 405
raise Lux.error.not_acceptable                         # 406
raise Lux.error.internal_server_error 'boom'           # 500
raise Lux.error.not_implemented                        # 501

# --- arbitrary status / generic ------------------------------------------

raise Lux.error 404                              # status 404, default message
raise Lux.error 418, "I'm a teapot"              # status + custom message
raise Lux.error 'generic'                        # status 400, custom message

# --- in-router use -------------------------------------------------------

def show
  @user = User.find(nav.ref) or raise Lux.error.not_found
  raise Lux.error.forbidden unless @user.can.read?
end

# --- conditional rendering across dev / prod -----------------------------

# dev: include the detailed message; prod: bare 404
raise Lux.error.not_found Lux.debug?('404 Not Found') {
  'Subdomain "%s" matched but nothing called' % name
}

# --- override the router :error action to customise rescue --------------

class ApplicationRouter < Lux::Router
  def error
    Lux.logger.error @error.message
    if @status == 404
      render :not_found
    else
      render :server_error
    end
  end
end

# --- format helpers ------------------------------------------------------

Lux::Error.inline(exception)         # inline panel (for embeds)
Lux::Error.format(exception, html: true, gems: false, message: true)

# --- logging -------------------------------------------------------------

Lux.error.log(exception)             # screen + error log + every on_log reporter

# register any number of reporters (web_common adds the exceptions log);
# each runs in its own rescue, re-registering from the same line replaces it
Lux.error.on_log { |error| MyExceptionStore.add error }
Lux.error.on_log { |error| Sentry.capture_exception error }
```

## Resolution order on raise

Handled by the innermost running router:

1. Its nearest `rescue_from` handler matching the error (`Lux::RescueFrom`),
   walking up to the root's (`Lux.router do rescue_from ... end`)
2. Else its `:error` action (default: JSON, the `error` template, or the
   framework error page)

The status comes from the error: a `Lux::Error` uses its own `status`, a policy denial (`Lux::Policy::Error`) is 403, anything else is 500.
The `:error` action receives `@error` (exception) and `@status` (that HTTP code) as instance variables.
In a `Lux::Api` the same rule holds: a `Lux::Error` answers with its own `status`.

## See also

* [`../router/README.md`](../router/README.md) - `rescue_from`, default `:error` action
