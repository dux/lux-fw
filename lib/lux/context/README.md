# Lux::Context

Thread-local context, always reached as `Lux.ctx`. Inside a request it
holds the request, response, params, session, nav and browser; everywhere
it holds a per-thread variable bag, memoize cache, locale and user.

## Outside a request

`Lux.ctx` is never nil. Outside a request (console, jobs, scripts,
`Lux.defer` from a job) it is built lazily without a request:

```ruby
Lux.ctx.request              # nil - this is the "inside a request?" check
Lux.ctx.var / .cache / .once # work, scoped to the thread
Lux.ctx.locale / .user       # work
Lux.ctx.no_cache?            # false
Lux.ctx.snapshot             # { request_id:, user: } with url/ip/method nil
Lux.ctx.response / .nav / .session / .params  # nil
Lux.url                      # raises: there is no request URL to build from
```

Request-bound code fails instead of reading a fake request.
`Lux::Context.new` starts a fresh request-less context;
`Lux::Context.new(url_or_env, opts)` builds one with a request (what the
router and `Lux.render.get` do).

## Full example

```ruby
class UsersRouter < ApplicationRouter
  before do
    @user = User.find_by_token(Lux.ctx.bearer_token) if Lux.ctx.bearer_token
    Lux.ctx.locale = Lux.ctx.session[:locale] || 'en'
  end

  def show
    # --- request / response ----------------------------------------------
    Lux.ctx.request          # Lux::Context::Request (a Rack::Request)
    Lux.ctx.response         # Lux::Response
    Lux.ctx.env              # raw Rack env

    # --- params + nav ----------------------------------------------------
    Lux.ctx.params           # validated/coerced if opt declared (Lux::Hash)
    Lux.ctx.nav.path         # canonical path array
    Lux.ctx.nav.ref          # captured id (see Router docs)

    # --- session (sealed cookie, see Session below) ---------------------
    Lux.ctx.session[:user_id] = @user.id
    Lux.ctx.session.clear

    # --- request-scoped vars --------------------------------------------
    Lux.ctx[:account] = @user.account             # shortcut for Lux.ctx.var[:account]
    Lux.ctx[:account]
    Lux.ctx.var                                    # full bag (Lux::Hash)

    # --- request-scoped memoize ------------------------------------------
    Lux.ctx.cache(:billing) { Billing.expensive_lookup(@user) }

    # --- once-per-request ------------------------------------------------
    Lux.ctx.once(:audit) { AuditLog.track(@user, 'viewed') }   # returns false on 2nd call

    # --- CSRF (see lib/lux/context/lib/csrf.rb) -------------------------
    Lux.ctx.csrf             # lazy 43-char token in session[:_csrf]
    Lux.ctx.csrf_valid?      # checks request _csrf / X-CSRF-Token
    Lux.ctx.csrf_required?   # non-GET/HEAD/OPTIONS, no Bearer, and a session cookie was sent

    # --- browser (master per-request: header / window / channel) ---------
    Lux.ctx.browser.header.title 'Home'
    Lux.ctx.browser.window[:app] = { cfg: { host: Lux.config.host },
                                     current: { user: @user.to_h } }
    Lux.ctx.browser.window_script       # <script id="lux-state">...</script>

    # --- encrypt / decrypt (per-request key; IP-bound, default 10m TTL) -
    token = Lux.ctx.encrypt(@user.id)
    Lux.ctx.decrypt(token)

    # --- background thread (Lux.ctx rebuilt from a snapshot) --------
    Lux.defer(context: @user) { |u| Mailer.deliver(:welcome, u.email) }
    Lux.defer { |snap| Audit.track(snap.user, snap.url) }      # snap = Lux.ctx.snapshot

    # --- request meta ----------------------------------------------------
    Lux.ctx.ip               # client IP (CF-Connecting-IP from a CF edge, else Rack#ip: XFF behind trusted proxies only)
    Lux.ctx.request_id       # X-Request-Id if sane, else random; echoed as x-request-id
    Lux.ctx.snapshot         # frozen { request_id, request_method, url, ip, user }
    Lux.ctx.host             # scheme://host:port
    Lux.ctx.uid              # unique id per call (each call returns a new id)
    Lux.ctx.bearer_token     # Authorization: Bearer <token>
    Lux.ctx.robot?
    Lux.ctx.mobile?
    Lux.ctx.no_cache?        # HTTP_CACHE_CONTROL=no-cache + can_clear_cache
    Lux.ctx.can_clear_cache = true   # opt-in for admin clears

    # --- locale ----------------------------------------------------------
    Lux.ctx.locale = :en

    # --- file tracking ---------------------------------------------------
    Lux.ctx.files_in_use                            # Set; touched files this request
  end
end
```

## Properties

| Property | Type | Notes |
|----------|------|-------|
| `request`         | `Lux::Context::Request` | the raw request (`Rack::Request` subclass; `xhr?` also true for fetch) |
| `response`        | `Lux::Response` | response builder |
| `nav`             | `Lux::Router::Nav` | canonical request path (see Nav below) |
| `route`           | `Lux::Router::Route` | router cursor |
| `session`         | `Lux::Context::Session` | sealed cookie session (see Session below) |
| `params`          | `Lux::Hash` | request params (coerced if `opt` declared) |
| `param_errors`    | hash | `{ field => 'Message' }` from the action's `opt` / `params do` contract, HTML requests only (JSON halts with 422). Empty when clean |
| `var`             | `Lux::Hash` | request-scoped bag (`Lux.ctx[:k]` shortcut) |
| `browser`         | `Lux::Browser` | master per-request object: `header` / `html` / `window` / `window_script` / `channel` |
| `locale`          | symbol/string | i18n hook |
| `env`             | hash | Rack env |
| `ip`              | string | client IP |
| `request_id`      | string | upstream `X-Request-Id` or a random id; echoed in the response, exception records and `Lux.defer` |
| `host`            | string | `request.base_url` (scheme://host, port only when non-default) |
| `uid`             | string | unique id per call |
| `bearer_token`    | string | `Authorization: Bearer <token>` |
| `robot?` / `mobile?` | bool | UA-based |
| `no_cache?`       | bool | `HTTP_CACHE_CONTROL=no-cache` + `can_clear_cache` |
| `can_clear_cache` | bool | opt-in for admin clears |
| `csrf` / `csrf_valid?` / `csrf_required?` | | CSRF surface (see `lib/csrf.rb`) |
| `rotate_csrf!`    | | drops the CSRF token; call on sign-in |
| `session_sid`     | string | stable per-session random id (guests too) |
| `local_request?`  | bool | client IP is loopback |
| `post`            | `Lux::Hash` | body-only params (form or JSON object body; mock `post:` wins) |
| `raw_body`        | string | request body, read once and rewound |
| `json_request?`   | bool | `Content-Type: application/json` |
| `malformed_request` | exception/nil | unparseable query/body or dot-segment path; answered with 400 |

## Helpers

| Helper | Notes |
|--------|-------|
| `Lux.ctx.cache(key) { ... }`    | request-scoped memoization |
| `Lux.ctx.once(key) { ... }`     | runs once per request; subsequent calls return false |
| `Lux.ctx.encrypt(data, ttl:)`   | signed JWT (tamper-proof, readable by the holder), IP-bound, default 10m TTL |
| `Lux.ctx.decrypt(token)`        | |
| `Lux.defer { \|snap\| ... }`    | bg thread; `snap` = `Lux.ctx.snapshot`; `Lux.ctx` inside is rebuilt from it (request id, method, url, `User.current=`); errors go to `Lux.error.log` |
| `Lux.defer(context: x) { \|x\| ... }` | bg thread with an explicit context value |
| `Lux.ctx.files_in_use`          | Set of files touched this request |
| `Lux.ctx.header`                | `browser.header` (title, meta, ...) |
| `Lux.ctx.render_html(...)`      | whole HTML document for a layout (`Lux::Browser::Html`) |
| `Lux::Context::EncryptParams.hidden_input(name, value)` | signed (readable, 1 day TTL) hidden `_data_*` field; decoded back into `params[name]` on submit |

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
* **Cookie name.** By default (`session_cookie_domain: nil`) the cookie is shared
  with the root domain (`Domain=example.com`, `__Secure-` over https).
  `session_cookie_domain: false` makes it host-only (`__Host-`, `Path=/`,
  `Secure`). The name also carries a 6-char hash of `Accept-Language` and a
  `_<port>` suffix, so a browser language change starts a fresh session.
* **Moving to a subdomain.** With a host-only cookie (`session_cookie_domain: false`)
  the cookie is not seen by other hosts.
  `nav.subdomain(:app, '/dashboard', session: true)` returns a same-host
  `/_lux_/handoff?to=<sealed target>` link with no session data in it, so the
  page can be cached or left open. Followed, it mints a one-time `?_lux_st=`
  token (sealed session data, valid 1 minute, for that host and this browser
  only) and redirects to the target. The receiving host merges it before any
  before-filter and 303-redirects to the same URL without the token. Only
  targets the app sealed, on the current domain, are accepted. A cross-site
  (`Sec-Fetch-Site: cross-site`) arrival with a token is ignored.
* **Device binding (DBSC).** Over https with a host-only cookie
  (`session_cookie_domain: false`) every session is offered
  [Device Bound Session Credentials](https://w3c.github.io/webappsec-dbsc/)
  once (`Secure-Session-Registration` header). Chrome/Edge register a TPM key
  at `/_lux_/dbsc/register` and from then on must sign a challenge at
  `/_lux_/dbsc/refresh` every 10 minutes to renew a proof cookie
  (`<session cookie>_b`); a bound session without a fresh proof is emptied, so a
  copied cookie dies off the device. Stateless - the public key is sealed into
  the session as `_k`. Other browsers ignore the header. Off with
  `session_dbsc: false`. See [`./lib/dbsc.rb`](./lib/dbsc.rb).
* **CF-* headers** are dropped by `Lux::Context::Request` unless the request came
  through a Cloudflare edge (or `cloudflare: true`), so `CF-IPCountry` and
  `CF-Connecting-IP` can be trusted wherever they are read.

## Nav

`Lux.ctx.nav` is the canonical request path. See
[`../router/lib/nav.rb`](../router/lib/nav.rb) for full DSL.

```ruby
nav.path                          # working path array - rewritten in place
nav.source_path                   # frozen, as the request arrived
nav.root                          # first segment
nav.child                         # second segment
nav.last                          # last segment
nav.format                        # :html / :json / etc (from .ext suffix)
nav.locale                        # locale extracted from path
nav.subdomain                     # TLD-aware subdomain
nav.subdomain(:app, '/x')         # URL on app.<domain> (nil -> the domain itself)
nav.subdomain(:app, '/x', session: true)  # ... carrying this session (see Session)
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

* [`../router/README.md`](../router/README.md) - routing
* [`../response/README.md`](../response/README.md) - response object
* [`../browser/README.md`](../browser/README.md) - `Lux.ctx.browser`
