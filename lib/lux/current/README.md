# Lux::Current

Thread-local request context. One object per request, available globally
as `Lux.current` (or just `current` inside controllers and APIs, or `lux`
anywhere). Holds the request, response, params, session, nav, and a
per-request variable bag.

## Small example

```ruby
current.params           # request params
current.session[:user]   # JWT-encrypted session
current.ip               # client IP
current.var[:foo] = 1    # request-scoped state
current[:foo]            # shortcut for current.var[:foo]
```

## Full example

```ruby
class UsersController < ApplicationController
  before do
    @user = User.find_by_token(current.bearer_token) if current.bearer_token
    Lux.current.locale = current.session[:locale] || 'en'
  end

  def show
    # request / response
    current.request          # Rack::Request
    current.response         # Lux::Response

    # params + nav
    current.params           # validated/coerced if opt declared
    current.nav.path         # canonical path array
    current.nav.ref          # captured :ref id

    # session (JWT)
    current.session[:user_id] = @user.id
    current.session.clear

    # request-scoped vars
    current[:account] = @user.account
    current[:account]                  # later in the same request
    current.var[:flash]                # full bag

    # request-scoped cache (memoization for THIS request)
    current.cache(:billing) { Billing.expensive_lookup(@user) }

    # run once per request, idempotent
    current.once(:audit) { AuditLog.track(@user, 'viewed') }

    # encrypt / decrypt with per-request key (IP-bound, TTL 10m default)
    token = current.encrypt(@user.id)
    current.decrypt(token)

    # background work (preserves Lux context)
    current.delay { Mailer.deliver(:welcome, @user.email) }

    # request meta
    current.ip
    current.host
    current.uid              # unique id per response
    current.robot?
    current.mobile?

    # locale
    current.locale = :en
  end
end
```

## Properties

| Property | Type | Notes |
|----------|------|-------|
| `request`         | `Rack::Request` | the raw request |
| `response`        | `Lux::Response` | response builder |
| `nav`             | `Lux::Application::Nav` | canonical request path |
| `route`           | `Lux::Application::Route` | router cursor |
| `session`         | `Lux::Current::Session` | JWT-encrypted session |
| `params`          | `Lux::Hash` | request params (coerced if `opt` declared) |
| `var`             | `Lux::Hash` | request-scoped bag (`current[:k]` shortcut) |
| `locale`          | symbol/string | i18n hook |
| `env`             | hash | Rack env |
| `ip`              | string | client IP (CF / X-Forwarded-For / REMOTE_ADDR) |
| `host`            | string | scheme://host:port |
| `uid`             | string | unique id per page (call multiple times → different) |
| `bearer_token`    | string | `Authorization: Bearer <token>` |
| `secure_token`    | string | sha1(IP) helper |
| `robot?` / `mobile?` | bool | UA-based |
| `no_cache?`       | bool | true if `HTTP_CACHE_CONTROL=no-cache` and `can_clear_cache` |
| `can_clear_cache` | bool | opt-in for admin clears |

## Helpers

```ruby
current.cache(key) { ... }       # request-scoped memoization
current.once(key) { ... }        # run once per request (returns false 2nd call)
current.encrypt(data, ttl:)      # JWT-encrypt, IP-bound default
current.decrypt(token)
current.delay { ... }            # background thread w/ Lux context preserved
current.files_in_use             # set of files touched this request
```

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

# id canonicalization (in a before filter)
nav.path(:ref) { |el| Ulid.is?(el) ? el : nil }
nav.ref / nav.refs                # captured ids
nav.pathname(has: 'edit')         # /foo/edit/x => true
```

## See also

* [`../application/README.md`](../application/README.md) - routing
* [`../response/README.md`](../response/README.md) - response object
* [`AGENTS.md`](./AGENTS.md) - LLM guide
