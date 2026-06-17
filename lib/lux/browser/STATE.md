# Client state convention: `window.app`

Status: accepted (2026-06-03), updated 2026-06-17

Server-injected client state is exported by `lux.browser.window` - a plain
Hash assigned onto the client `window` by `lux.browser.window_script`. The framework
guarantees only two lines (`window.app = window.app || {};` and
`window.app.page = {};`); everything else is just the hash you set. The
structure below is a **convention**, not enforced machinery - it's how you
shape `window[:app]`.

By convention all page data lives under a single root, `window.app`, split
into three buckets - do not park request data on ad-hoc `window.*` globals or
inside library namespaces.

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
| `app.page`      | the current page's payload              | **reset every render** by `export`; never carries over |

Mirrors the server vocabulary: `app.current.user` <-> `lux.current.user`.

## Lifetimes

`window_script` resets `window.app.page = {};` on every render, then **merges**
`window[:app]` into `window.app` (`Object.assign(window.app, ...)`):

* `cfg` / `current` you set are merged in; the ones you do **not** set survive
  from an earlier render, so config/identity **persist** across pjax hops.
* `page` is reset to `{}` first, so it is wiped every render; whatever your
  `app` provides under `page` wins over the reset.
* `page` is volatile by design: page B never reads page A's leftovers.

Non-`app` top-level keys (`window[:api] = {...}`) are assigned onto the global
`window` instead - reserve them to namespaces, avoid native window names.

## Usage

```ruby
# server (controller / before-filter)
lux.browser.window[:app] = {
  cfg:     { host: Lux.config.host, deploy_id: Lux::DEPLOY_ID },
  current: { user: lux.user&.to_h },
  page:    { title: 'Home' },            # reset on next navigation
}
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

Other top-level keys (`lux.browser.window[:api] = { url: '/api' }` ->
`window.api`) work for cases that genuinely need a separate global, but
app/page data belongs in `app`.

## Rules

* Server data -> `app.cfg` / `app.current` / `app.page`. Nothing else.
* Custom function globals -> `app.fn.*` (old `window.X` names kept as aliases).
* `page` is request-scoped: assume it is wiped on every navigation.
* No secrets - everything here is visible in page source (`Lux.csrf` lives
  under `window.Lux`, not `app`).
