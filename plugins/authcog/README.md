# Lux.plugin :authcog

Central-auth sign-in for a Lux app, usable without the html builders, asset
helpers and exception logger of `web_common`.

```yaml
# config/config.yaml
default:
  plugins:
    - db
    - authcog
```

An app with `web_common` lists `authcog` next to it; `web_common` does not
pull it in.

Needs the `db` plugin and an app-side `User` model - see **Requirements**.

## What it provides

| Constant | Role | Loaded from |
|----------|------|-------------|
| `AuthcogRouter` | Sign-in entry point + callback landing. Exchanges a one-time hash, bound to a per-browser challenge, for a local session. | `load/authcog_router.rb` |
| `UserSession` | Session identity, `?sso_action=` links, sudo overlay, API-key login. | `load/user_session.rb` |

## Wiring

```ruby
# app/routes.rb
Lux.router do
  before do
    UserSession.resolve
    UserSession.destroy_session if user && (user.is_locked || user.is_deleted)
  end

  route do
    map '/authcog', 'authcog#call'   # callback landing
    map '/login',   'main#login'     # your action, redirects to the auth link
    root 'main#index'
  end
end
```

```ruby
# the /login action
def login
  redirect_to '/' if user
  redirect_to AuthcogRouter.auth_link
end
```

`UserSession.resolve` must run before routing. It restores `User.current` from
the session cookie, a bearer token, or a `?sso_action=` link, so `user` is set
by the time a router runs.

## The flow

1. `auth_link` is just `/authcog`, so it can be linked from any view or layout.
2. Following it hits `AuthcogRouter#start`, which mints a one-time challenge,
   keeps it in the visitor's session, and redirects to
   `https://<realm>.authcog.com/domain:<host>[/port:<port>]?state=<challenge>`.
3. Central auth signs the person in and sends the browser back to
   `/authcog?callback=<40-char hash>&state=<challenge>`.
4. `AuthcogRouter#callback` spends the challenge, then exchanges the hash
   server-side for `{ email, name, avatar, provider }`, calls
   `User.quick_create(email)`, and writes `session[:user_ref]`.
5. It redirects to `session[:redirect_after_login]` or `/`.

The hash is single-use and scoped to the requesting domain, so it is worthless
to anyone who intercepts it on another host. The domain comes from the request
only when it sits inside the domain of `Lux.config.host` (subdomains
included); any other Host header falls back to the configured host, so a
forged header cannot pick the domain a stolen hash is exchanged for.
On a shared suffix (`herokuapp.com`, `github.io`, `vercel.app`) that domain
includes strangers, so set `authcog_hosts` to the exact hosts to trust instead.
Both the hand-off and the server-side exchange use the same guarded host
(`Authcog.relying_url`). The challenge is what makes the
callback belong to this browser: a login someone else started cannot be landed
in a visitor's session (RFC 9700).

The challenge is minted when the link is followed, never when it is drawn, so
`auth_link` holds no secret and stays safe in a shared layout or a cached page.
A browser may hold several outstanding challenges (`Authcog.mint_challenge`
keeps the last 4 by default, `limit:`), because a
visitor can open the sign-in link in more than one tab; only a matching one is
ever spent, so a bogus `?state=` cannot clear a real one.

## Login links

`UserSession.login_link(user, ttl: 1.hour)` builds a `?sso_action=` magic link
(mailers, cross-host, admin login-as).
It is one-time: a nonce in the sealed token is marked spent in `Lux.cache` on first use, so a forwarded or logged link cannot sign in again.

## Sign-out

`UserSession.logout_link` builds a `?sso_action=` URL carrying a sealed (encrypted),
5-minute `logout` token. `resolve` consumes it on the next request. It reads
`User.current.ref`, so guard it:

```haml
- if user
  %a{ href: UserSession.logout_link } Sign out
```

## Requirements

* The `db` plugin, for `User.take` and `User.find_by`.
* A `User` model with `ref`, `email`, `name`, `is_locked`, `is_deleted`, and a
  `User.quick_create(email)` class method. `cached_avatar` and `api_key` are
  optional and enable avatar storage and bearer-token login when present.
* `User.current` / `User.current=` on the model, usually via `ApplicationModel`.
* `secret` in `config/config.yaml` - `Lux::Utils::Crypt` signs the
  `?sso_action=` tokens with it.

## Config

| Key | Default | Meaning |
|-----|---------|---------|
| `authcog_realm` | `auth` | Subdomain of `authcog.com` to authenticate against. |
| `authcog_path` | `/authcog` | Where this router is mounted; what `auth_link` returns. |
| `host` | - | The app's own URL; its domain bounds which request hosts sign-in trusts. |
| `authcog_hosts` | - | Exact request hosts sign-in trusts (e.g. `[app.example.com, www.example.com]`); when set, replaces the domain match. |

## Redirect after login

```ruby
UserSession.redirect_after_login = request.path   # before bouncing to /login
```

`AuthcogRouter#callback` consumes the same session key, so a guest who hits
a protected page lands back on it after signing in. Only site-local paths are
kept (`UserSession.local_path`): a full URL or a protocol-relative `//host`
is dropped, so the redirect cannot be turned into an open redirect.
