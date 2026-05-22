# Lux::Current

Thread-local request context. One object per request, available as
`Lux.current` or just `current` inside controllers and APIs, or `lux`
anywhere. Holds the request, response, params, session, nav, browser,
and a per-request variable bag.

## Full example

```ruby
class UsersController < ApplicationController
  before do
    @user = User.find_by_token(current.bearer_token) if current.bearer_token
    Lux.current.locale = current.session[:locale] || 'en'
  end

  def show
    # --- request / response ----------------------------------------------
    current.request          # Rack::Request
    current.response         # Lux::Response
    current.env              # raw Rack env

    # --- params + nav ----------------------------------------------------
    current.params           # validated/coerced if opt declared (Lux::Hash)
    current.nav.path         # canonical path array
    current.nav.ref          # captured :ref id (see Application docs)

    # --- session (JWT-encrypted) ----------------------------------------
    current.session[:user_id] = @user.id
    current.session.clear

    # --- request-scoped vars --------------------------------------------
    current[:account] = @user.account             # shortcut for current.var[:account]
    current[:account]
    current.var[:flash]                            # full bag (Lux::Hash)

    # --- request-scoped memoize ------------------------------------------
    current.cache(:billing) { Billing.expensive_lookup(@user) }

    # --- once-per-request ------------------------------------------------
    current.once(:audit) { AuditLog.track(@user, 'viewed') }   # returns false on 2nd call

    # --- CSRF (see lib/lux/current/lib/csrf.rb) -------------------------
    current.csrf             # lazy 6-char token in session[:_csrf]
    current.csrf_valid?      # checks request _csrf / X-CSRF-Token
    current.csrf_required?   # true for non-GET without Bearer auth

    # --- browser state (per-request, emits to window.<root>) -------------
    current.browser.app.config.host = Lux.config.host
    current.browser.app.data.user   = @user.to_h
    current.browser.script_tag       # <script id="lux-state">...</script>

    # --- encrypt / decrypt (per-request key; IP-bound, default 10m TTL) -
    token = current.encrypt(@user.id)
    current.decrypt(token)

    # --- background thread (clean Lux.current inside) -------------------
    Lux.defer(context: @user) { |u| Mailer.deliver(:welcome, u.email) }
    Lux.defer { |ctx| Audit.track(ctx.user) }                  # ctx = Lux.current.dup

    # --- request meta ----------------------------------------------------
    current.ip               # client IP (CF / X-Forwarded-For / REMOTE_ADDR)
    current.host             # scheme://host:port
    current.uid              # unique id per call (each call returns a new id)
    current.bearer_token     # Authorization: Bearer <token>
    current.secure_token     # sha1(IP); secure_token(t) → t == secure_token
    current.robot?
    current.mobile?
    current.no_cache?        # HTTP_CACHE_CONTROL=no-cache + can_clear_cache
    current.can_clear_cache = true   # opt-in for admin clears

    # --- locale ----------------------------------------------------------
    current.locale = :en

    # --- file tracking ---------------------------------------------------
    current.files_in_use                            # Set; touched files this request
  end
end
```

## Properties

| Property | Type | Notes |
|----------|------|-------|
| `request`         | `Rack::Request` | the raw request |
| `response`        | `Lux::Response` | response builder |
| `nav`             | `Lux::Application::Nav` | canonical request path (see Nav below) |
| `route`           | `Lux::Application::Route` | router cursor |
| `session`         | `Lux::Current::Session` | JWT-encrypted session |
| `params`          | `Lux::Hash` | request params (coerced if `opt` declared) |
| `var`             | `Lux::Hash` | request-scoped bag (`current[:k]` shortcut) |
| `browser`         | `Lux::Browser` | per-request client-state accumulator |
| `locale`          | symbol/string | i18n hook |
| `env`             | hash | Rack env |
| `ip`              | string | client IP |
| `host`            | string | scheme://host:port |
| `uid`             | string | unique id per call |
| `bearer_token`    | string | `Authorization: Bearer <token>` |
| `secure_token`    | string | sha1(IP) helper |
| `robot?` / `mobile?` | bool | UA-based |
| `no_cache?`       | bool | `HTTP_CACHE_CONTROL=no-cache` + `can_clear_cache` |
| `can_clear_cache` | bool | opt-in for admin clears |
| `csrf` / `csrf_valid?` / `csrf_required?` | | CSRF surface (see `lib/csrf.rb`) |

## Helpers

| Helper | Notes |
|--------|-------|
| `current.cache(key) { ... }`    | request-scoped memoization |
| `current.once(key) { ... }`     | runs once per request; subsequent calls return false |
| `current.encrypt(data, ttl:)`   | JWT-encrypt, IP-bound by default |
| `current.decrypt(token)`        | |
| `Lux.defer { \|ctx\| ... }`     | bg thread; `ctx` = `Lux.current.dup`, fresh `Lux.current` inside |
| `Lux.defer(context: x) { \|x\| ... }` | bg thread with an explicit context value |
| `current.files_in_use`          | Set of files touched this request |

## Nav

`current.nav` is the canonical request path - routing inspects it but
does not mutate. See [`./lib/nav.rb`](./lib/nav.rb) for full DSL.

```ruby
nav.path                          # canonical path array
nav.root                          # first segment
nav.child                         # second segment
nav.last                          # last segment
nav.format                        # :html / :json / etc (from .ext suffix)
nav.locale                        # locale extracted from path
nav.subdomain                     # TLD-aware subdomain
nav.domain                        # bare domain
nav.base                          # scheme://host:port
nav.url(foo: 1)                   # current URL + query merge

# id canonicalisation (typically in a before filter)
nav.path(:ref) { |el| Ulid.is?(el) ? el : nil }
nav.ref / nav.refs                # captured ids
nav.pathname(has: 'edit')         # /foo/edit/x => true
```

## See also

* [`../application/README.md`](../application/README.md) - routing
* [`../response/README.md`](../response/README.md) - response object
* [`../browser/README.md`](../browser/README.md) - `current.browser`
* [`AGENTS.md`](./AGENTS.md) - LLM guide
