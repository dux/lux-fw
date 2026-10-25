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

# --- error pages via rescue_from ----------------------------------------

Lux.router do
  rescue_from { |err| map 'main#error' }   # MainRouter#error renders app/views/main/error.haml
end

class MainRouter < ApplicationRouter
  def error
    render(@status == 404 ? :not_found : :error)
  end
end

# --- format helpers ------------------------------------------------------

Lux::Error.format(exception, html: true, gems: false, message: true)
Lux::Error.copy_button(exception, status)   # dev-only "Copy for LLM" button

# --- logging -------------------------------------------------------------

Lux.error.log(exception)             # screen + error log + every on_log reporter

# register any number of reporters (web_common adds the exceptions log);
# each runs in its own rescue, re-registering from the same line replaces it
Lux.error.on_log { |error| MyExceptionStore.add error }
Lux.error.on_log { |error| Sentry.capture_exception error }
```

## Resolution order on raise

Handled by the innermost running router:

1. The first error goes to its nearest `rescue_from` handler matching the error (`Lux::RescueFrom`), walking up to the root's (`Lux.router do rescue_from ... end`).
2. If that handler raises, the answer is a 500 dump (message and backtrace in debug only).
3. No handler, or a handler that renders nothing: the default error screen (JSON for JSON requests, else the framework error page).

Template exceptions raise too, so they follow the same order.
The status comes from the error: a `Lux::Error` uses its own `status`, a policy denial (`Lux::Policy::Error`) is 403, anything else is 500.
The handler, and any action it maps to, sees `@error` (exception) and `@status` (that HTTP code) as instance variables.
In a `Lux::Api`, a `Lux::Error` also answers with its own `status`.

## See also

* [`../router/README.md`](../router/README.md) - `rescue_from` and the error rule
