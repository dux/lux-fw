# Client state convention: `window.app`

Status: accepted (2026-06-03)

All server-injected client state lives under a single root, `window.app`,
split into three level-2 buckets. This is the only place page data belongs -
do not park request data on ad-hoc `window.*` globals or inside library
namespaces.

`window.app` is also the home for custom function globals, under
`window.app.fn` (`app.fn.Api`, `app.fn.Toast`, `app.fn.ApiForm`, ...). So the
single `app` root carries both *data* (cfg/current/page) and *code* (fn).
The core selector `$` / `Z` stays a top-level global; moved helpers keep their
old `window.X` names as back-compat aliases.

## The three data buckets

| Bucket          | Holds                                   | Lifetime / pjax behaviour                          |
|-----------------|-----------------------------------------|----------------------------------------------------|
| `app.cfg`       | static app config: host, locale, deploy id, feature flags | set once; **survives** navigations until re-set |
| `app.current`   | session / identity: `current.user`, permissions | survives until it actually changes (login/logout) |
| `app.page`      | the current page's payload              | **replaced on every navigation**; never carries over |

Mirrors the server vocabulary: `app.current.user` <-> `lux.current.user`.

## Why three, and why these lifetimes

Emit is atomic per level-2 bucket (see [README](./README.md) "Emit rule"):
a bucket the new render sets is replaced wholesale; a bucket it does *not*
set survives on the client across a pjax swap. That gives us exactly two
persistence classes for free:

* `cfg` and `current` are usually unset on a normal page render, so they
  **persist** - no need to re-ship config/identity on every pjax hop.
* `page` is volatile: it must **not** persist, or page B would read page A's
  leftovers. To guarantee this, `script_tag` always emits `app.page`
  (as `{}` when the render set nothing), so each navigation overwrites and
  clears the previous page's payload. This is the one bucket name the
  framework knows about by name.

## Usage

```ruby
# server (controller / before-filter)
lux.browser.app.cfg.host      = Lux.config.host
lux.browser.app.cfg.deploy_id = Lux::DEPLOY_ID
lux.browser.app.current.user  = lux.user&.to_h
lux.browser.app.page.title    = 'Home'           # cleared on next navigation
```

```js
// client - data
window.app.cfg.host
window.app.current.user
window.app.page.title

// client - functions
window.app.fn.Toast('saved')
window.Toast('saved')                            // back-compat alias, same fn
```

Root namespace is `Lux.config.browser_namespace` (default `app`). Other
top-level roots (`lux.browser.api.url` -> `window.api`) still work for cases
that genuinely need a separate global, but app/page data belongs in `app`.

## Rules

* Server data -> `app.cfg` / `app.current` / `app.page`. Nothing else.
* Custom function globals -> `app.fn.*` (old `window.X` names kept as aliases).
* `page` is request-scoped: assume it is wiped on every navigation.
* No secrets - everything here is visible in page source (`Lux.csrf` lives
  under `window.Lux`, not `app`).
