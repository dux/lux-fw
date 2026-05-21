# Lux::Error - agent guide

Error class + raise helpers. **The status lives on the response, not the
exception** - the helpers set both.

## Canonical example

```ruby
# raise with the right HTTP status
Lux.error.not_found 'no such user'              # 404
Lux.error.forbidden                              # 403, message defaults
Lux.error.bad_request 'name missing'            # 400
Lux.error.unauthorized                          # 401
Lux.error.internal_server_error                 # 500
Lux.error(418, "I'm a teapot")                   # arbitrary

# render an exception object (only used by the framework's last-resort)
Lux::Error.render(err)
Lux::Error.inline(err)
```

## Rules

* **Use the helpers, not raw `raise`.** They set `response.status` AND
  raise `Lux::Error`, so the framework's dispatch chain finds the right
  `:error` action.
* **Dev/prod-conditioned messages** via `Lux.mode.errors?('short') { 'long' }`.
  In production the helper-block evaluates to `'short'`; in dev it runs
  the block and uses its return value.
* **Custom `:error` action** on a controller receives `@error` and
  `@status` as ivars. Use them, don't refetch.
* **`rescue_from` on the app** (router level) wins over controller-level
  `:error`. Use for cross-cutting error views (api vs html, logged-in
  vs not).
* **HTTP status helpers** cover the common codes (400-406, 500, 501).
  For others use `Lux.error(code, msg)`.

## Don't

* `raise StandardError.new` and expect the right status - the response
  status stays at 200/whatever-it-was, then the framework defaults to
  500.
* Build your own error JSON in controllers - the default `:error`
  already does sensible JSON for `nav.format == :json`. Override only if
  your shape differs.
* Log inside `:error` AND `rescue_from` - they both fire on the same
  exception in some paths. Pick one.

## See also

* [`Lux::Application` AGENTS](../application/AGENTS.md) - `rescue_from`
* [`Lux::Controller` AGENTS](../controller/AGENTS.md) - `:error` action
