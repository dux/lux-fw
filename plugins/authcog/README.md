# Lux.plugin :authcog

Central-auth sign-in for a Lux app. Split out of `web_common` so an app can
take authentication without the html builders, asset helpers and exception
logger that come with the full web layer.

```yaml
# config/config.yaml
default:
  plugins:
    - db
    - authcog
```

`web_common` declares this plugin as a dependency, so an app that lists
`web_common` gets both constants without naming `authcog` itself.

Needs the `db` plugin and an app-side `User` model - see **Requirements**.

## What it provides

| Constant | Role | Loaded from |
|----------|------|-------------|
| `AuthcogController` | Callback landing. Exchanges a one-time hash for a local session. | `load/authcog_controller.rb` |
| `UserSession` | Session identity, `?sso_action=` links, sudo overlay, API-key login. | `load/user_session.rb` |

## Wiring

```ruby
# app/routes.rb
Lux.app do
  before do
    UserSession.resolve
    UserSession.destroy_session if user && (user.is_locked || user.is_deleted)
  end

  routes do
    map '/authcog', 'authcog#call'   # callback landing
    map '/login',   'main#login'     # your action, redirects to the auth link
    root 'main'
  end
end
```

```ruby
# the /login action
def login
  return redirect_to '/' if user
  redirect_to AuthcogController.auth_link
end
```

`UserSession.resolve` must run before routing. It restores `User.current` from
the session cookie, a bearer token, or a `?sso_action=` link, so `user` is set
by the time a controller runs.

## The flow

1. `/login` redirects to `https://<realm>.authcog.com/domain:<host>[/port:<port>]`.
2. Central auth signs the person in and sends the browser back to
   `/authcog?callback=<40-char hash>`.
3. `AuthcogController#callback` exchanges that hash server-side for
   `{ email, name, avatar, provider }`, calls `User.quick_create(email)`, and
   writes `session[:user_ref]`.
4. It redirects to `session[:redirect_after_login]` or `/`.

The hash is single-use and scoped to the requesting domain, so it is worthless
to anyone who intercepts it on another host.

## Sign-out

`UserSession.logout_link` builds a `?sso_action=` URL carrying an encrypted,
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

## Redirect after login

```ruby
UserSession.redirect_after_login = request.path   # before bouncing to /login
```

`AuthcogController#callback` consumes the same session key, so a guest who hits
a protected page lands back on it after signing in.
