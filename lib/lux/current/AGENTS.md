# Lux::Current - agent guide

Thread-local request context. One per request, lives in `Thread.current[:lux]`.
Accessible as `Lux.current`, `current`, or `lux` from any context.

## Canonical example

```ruby
class UsersController < ApplicationController
  before do
    @user = User.find_by_token(current.bearer_token) if current.bearer_token
    current.locale = current.session[:locale] || 'en'
  end

  def show
    current.session[:user_id] = @user.id   # JWT-encrypted session

    current[:account] = @user.account      # request-scoped bag
    current.cache(:billing) { Billing.expensive_lookup(@user) }
    current.once(:audit)  { AuditLog.track(@user, 'viewed') }

    Lux.defer { |ctx| Mailer.deliver(:welcome, ctx.session[:email]) }
    Lux.defer(context: @user) { |u| Mailer.deliver(:welcome, u.email) }
  end
end
```

## Rules

* **One object per request**, lives in `Thread.current[:lux]`. Don't pass
  it around; just reach for `current` / `lux`.
* **`current.var`** is for request-scoped state. **`current.session`** is
  JWT-encoded, sent to the client as a cookie - keep small and don't
  store secrets that shouldn't reach the browser.
* **`current[:k]`** is sugar for `current.var[:k]`. Use for transient
  per-request state across before-filters / actions / views.
* **`current.cache(key) { ... }`** memoizes for the lifetime of THIS
  request. For cross-request caching use [`Lux.cache`](../cache/AGENTS.md).
* **`current.once(key)`** returns truthy the first time, falsy after.
  Useful for "do this at most once per request" patterns.
* **`Lux.defer { |ctx| ... }`** spawns a thread with a **clean** `Lux.current`.
  The parent context is passed explicitly as the block arg (a shallow dup of
  `Lux.current`). Use `Lux.defer(context: x) { |x| ... }` to override. Reach
  for the explicit `ctx`, not `Lux.current`, inside the block. Zero-arity
  blocks (`Lux.defer { ... }`) still work.
* **`current.locale`** is the i18n entry point. Read it inside templates,
  set it in a `before` filter.
* **`current.ip`** is CF-aware (HTTP_CF_CONNECTING_IP first).
* **`nav.path(:ref) { |el| ... }`** canonicalizes id segments to `:ref`
  symbols. Call inside a `before` filter to drive resourceful routing.

## Don't

* Don't store secrets in `current.session` - it's encrypted but reaches
  the client.
* Don't mutate `current.nav.path` after routing has started - use
  `lux.route` as the routing cursor.
* Don't bypass `Lux.defer` with raw `Thread.new` - you lose the timeout
  guard and error logging.
* Don't read `Lux.current` inside a `Lux.defer` block expecting parent
  request state - use the explicit `ctx` arg instead.
* Don't use `Thread.current[:lux]` directly - go through `Lux.current`
  or `lux`.

## See also

* [`Lux::Application` AGENTS](../application/AGENTS.md) - nav, routing
* [`Lux::Response` AGENTS](../response/AGENTS.md) - via `current.response`
* [`Lux::Cache` AGENTS](../cache/AGENTS.md) - cross-request caching
