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
    current.request          # Lux::Current::Request (a Rack::Request)
    current.response         # Lux::Response
    current.env              # raw Rack env

    # --- params + nav ----------------------------------------------------
    current.params           # validated/coerced if opt declared (Lux::Hash)
    current.nav.path         # canonical path array
    current.nav.ref          # captured id (see Application docs)

    # --- session (sealed cookie, see Session below) ---------------------
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

    # --- browser (master per-request: header / window / channel) ---------
    current.browser.header.title 'Home'
    current.browser.window[:app] = { cfg: { host: Lux.config.host },
                                     current: { user: @user.to_h } }
    current.browser.window_script       # <script id="lux-state">...</script>

    # --- encrypt / decrypt (per-request key; IP-bound, default 10m TTL) -
    token = current.encrypt(@user.id)
    current.decrypt(token)

    # --- background thread (Lux.current rebuilt from a snapshot) --------
    Lux.defer(context: @user) { |u| Mailer.deliver(:welcome, u.email) }
    Lux.defer { |ctx| Audit.track(ctx.user, ctx.url) }         # ctx = Lux.current.snapshot

    # --- request meta ----------------------------------------------------
    current.ip               # client IP (CF-Connecting-IP from a CF edge, else Rack#ip: XFF behind trusted proxies only)
    current.request_id       # X-Request-Id if sane, else random; echoed as x-request-id
    current.snapshot         # frozen { request_id, request_method, url, ip, user }
    current.host             # scheme://host:port
    current.uid              # unique id per call (each call returns a new id)
    current.bearer_token     # Authorization: Bearer <token>
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
| `request`         | `Lux::Current::Request` | the raw request (`Rack::Request` subclass; `xhr?` also true for fetch) |
| `response`        | `Lux::Response` | response builder |
| `nav`             | `Lux::Application::Nav` | canonical request path (see Nav below) |
| `route`           | `Lux::Application::Route` | router cursor |
| `session`         | `Lux::Current::Session` | sealed cookie session (see Session below) |
| `params`          | `Lux::Hash` | request params (coerced if `opt` declared) |
| `param_errors`    | hash | `{ field => 'Message' }` from the action's `opt` / `params do` contract, HTML requests only (JSON halts with 422). Empty when clean |
| `var`             | `Lux::Hash` | request-scoped bag (`current[:k]` shortcut) |
| `browser`         | `Lux::Browser` | master per-request object: `header` / `window` / `export` / `channel` |
| `locale`          | symbol/string | i18n hook |
| `env`             | hash | Rack env |
| `ip`              | string | client IP |
| `request_id`      | string | upstream `X-Request-Id` or a random id; echoed in the response, exception records and `Lux.defer` |
| `host`            | string | scheme://host:port |
| `uid`             | string | unique id per call |
| `bearer_token`    | string | `Authorization: Bearer <token>` |
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
| `Lux.defer { \|ctx\| ... }`     | bg thread; `ctx` = `Lux.current.snapshot`; `Lux.current` inside is rebuilt from it (request id, method, url, `User.current=`); errors go to `Lux.error.log` |
| `Lux.defer(context: x) { \|x\| ... }` | bg thread with an explicit context value |
| `current.files_in_use`          | Set of files touched this request |

## Session

The whole session lives in one sealed (AES-256-GCM) cookie - there is no server
store. Rules, in [`./lib/session.rb`](./lib/session.rb):

* **Sliding lifetime.** `session_cookie_max_age` (default 10 days) is both the
  cookie `Max-Age` and the TTL sealed inside it. A cookie older than a day is
  reissued on the next response, so a daily visitor is never logged off and one
  gone longer than max age is.
* **Browser check.** User-Agent (version numbers dropped, so updates do not log
  out) plus `CF-IPCountry` is hashed into `_c`; a mismatch empties the session.
  `session_ip_check: true` adds the exact IP.
* **Cookie name.** Over https the name carries `__Host-` (host-only, `Path=/`,
  `Secure`), so a subdomain or plain-http page cannot plant one. Setting
  `session_cookie_domain` shares the cookie with subdomains and switches to
  `__Secure-`.
* **CF-* headers** are dropped by `Lux::Current::Request` unless the request came
  through a Cloudflare edge (or `cloudflare: true`), so `CF-IPCountry` and
  `CF-Connecting-IP` can be trusted wherever they are read.

## Nav

`current.nav` is the canonical request path - routing inspects it but
does not mutate. See [`../application/lib/nav.rb`](../application/lib/nav.rb) for full DSL.

```ruby
nav.path                          # working path array - rewritten in place
nav.source_path                   # frozen, as the request arrived
nav.root                          # first segment
nav.child                         # second segment
nav.last                          # last segment
nav.format                        # :html / :json / etc (from .ext suffix)
nav.locale                        # locale extracted from path
nav.subdomain                     # TLD-aware subdomain
nav.domain                        # bare domain
nav.base                          # scheme://host:port
nav.url(foo: 1)                   # current URL + query merge

# id classification (one line in a router before filter)
nav.map_path                      # format from Lux.config.ref_format
nav.map_path :uuid7               # or a different registered format
nav.map_path { |el| ... }         # or a custom rule
nav.ref / nav.refs                # captured ids
nav.pathname(has: 'edit')         # /foo/edit/x => true
```

Three views of the path:

| reader | what it is |
|--------|------------|
| `nav.source_path` | frozen snapshot of what arrived |
| `nav.path` | the working copy, mutated in place |
| `nav.normalized_path` | the working copy as a *shape* - ids back as `'ref'` |

`nav.path` is the working copy: `nav.ref` swaps id segments for a
`Nav::Base` instance carrying the id (see
[`../../../doc/migration-nav-ref.md`](../../../doc/migration-nav-ref.md)),
`nav.locale { }` peels a leading `/xx`, and app code edits it directly
(`nav.path[1] = board.ref`).

`nav.normalized_path` is that same working copy with every classified id put
back as the literal `'ref'` - `/boards/abc123/edit` reads
`['boards', 'ref', 'edit']`. That is the form that maps to disk, so
`auto_render` uses it to find `app/views/boards/ref/edit.haml`.

`nav.source_path` is a frozen snapshot taken at the
end of `Nav#initialize` - lowercased, format and `key:value` already stripped, but
before any of that rewriting. Reach for it when you need the path a second time
and something in between may have changed it:

```ruby
'/' + nav.source_path.join('/')   # stable canonical pathname
```

It is not `request.path`, which is the raw Rack string: original case, extension
and `key:value` segments intact, and not split into segments.

## See also

* [`../application/README.md`](../application/README.md) - routing
* [`../response/README.md`](../response/README.md) - response object
* [`../browser/README.md`](../browser/README.md) - `current.browser`
