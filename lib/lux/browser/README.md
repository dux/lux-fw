# Lux::Browser

Two roles in one class:

1. **Class-level** - server-side composer for the `window.Lux` client
   surface. Subsystems register JS modules; the composed bundle is served
   at `/_lux_/*.js` (a reserved framework path).
2. **Instance-level** - the master per-request object, accessed via
   `lux.browser` (instantiated by `Lux::Current#browser`). It owns the
   browser-facing pieces:

   | call | returns |
   |------|---------|
   | `lux.browser.header` | `Lux::Browser::Header` - the `<head>` builder |
   | `lux.browser.window` | a plain `Hash`, exported onto the client `window` |
   | `lux.browser.window_script` | the `<script>` that writes the window hash (emitted by `header.render`) |
   | `lux.browser.bundle(*mods)` | composed client JS bundle |
   | `lux.browser.channel(name)` | SSE channel publisher (same as `Lux.channel`) |
   | `lux.browser.publish(name, data)` | broadcast on a channel |

   `header` is its own class; `window` is just a Hash. `lux.header` is a
   pointer to `lux.browser.header`.

## Full example

```ruby
# --- CLASS-LEVEL: JS bundling (boot-time, in any subsystem) ---

Lux::Browser.register :sse, file: 'assets/lux/sse.js'    # registers a module
Lux.browser.modules                                       # [:core, :sse, ...]
Lux.browser.registered?(:sse)                             # true
Lux.browser.client_js                                     # all modules, core first
Lux.browser.client_js(:sse)                               # core + sse only
Lux.browser.client_js(:sse, :api)                         # core + listed

# Served URLs (intercepted before route resolution; /_lux_/* is reserved):
#   /_lux_/client.js                  -> all registered modules
#   /_lux_/client.js?modules=sse,api  -> just those
#   /_lux_/<name>.js                  -> core + that one (404 if unknown)

# --- INSTANCE-LEVEL: per-request (controller / before-filter) ---

# header (<head> builder)
lux.browser.header.title       'Home'
lux.browser.header.description  'short summary'

# window - a plain Hash, unrestricted; set whatever you want. The :app bucket
# is pre-seeded, so controllers can accumulate into it incrementally:
lux.browser.window[:app][:cfg]     = { host: Lux.config.host, locale: lux.locale }
lux.browser.window[:app][:current] = { user: lux.user&.to_h }
lux.browser.window[:api]           = { url: '/api' }    # extra top-level key

# channel (SSE publish) / bundle (client bundle)
lux.browser.channel(:notifications).push(message: 'Hello')
lux.browser.publish(:notifications, message: 'Hello')   # same thing, shorthand
lux.browser.bundle(:sse)                                # core + sse bundle

# --- EMIT in the layout head ---
# lux.browser.header.render emits window_script for you, so a single call in
# the layout %head emits both the head tags and the window bootstrap (do NOT
# also call window_script yourself - one emitter, one #lux-state tag):
#
#   = lux.browser.header.render do |el|
#     = el.postwind
#
# the window part renders as:
#   <script id="lux-state">
#     window.app = window.app || {};
#     window.app.page = {};
#     Object.assign(window.app, {"cfg":{...},"current":{...}});
#     Object.assign(window, {"api":{"url":"/api"}});
#   </script>
```

## Export rule

`window_script` is deliberately tiny:

* `window.app = window.app || {};` - the one guaranteed bootstrap, so bundles
  can drop defensive `window.app ||= {}` guards.
* `window.app.page = {};` - the volatile `page` bucket is reset on every render,
  so a pjax navigation never inherits the previous page's payload.
* `Object.assign(window.app, <hash[:app]>)` - the `:app` key is **merged** into
  `window.app`, so `cfg`/`current` persist across pjax and the `page` reset
  survives unless your `app` provides its own `page`.
* `Object.assign(window, <other keys>)` - any non-`app` top-level keys are
  assigned onto the client `window` directly.
* `</` in string values is escaped to `<\/` so a payload can't break out of the
  surrounding `<script>` tag.

Note: non-`app` keys land on the **global** `window` (`window[:api]` ->
`window.api`). Use namespaced roots and avoid native window names
(`name`, `location`, `status`, `top`, `length`, ...).

The `app.cfg` / `app.current` / `app.page` split is a convention (see
[STATE.md](./STATE.md)), not enforced by the framework - it's just how you
structure `window[:app]`.

## Security

Don't ship secrets via `lux.browser.window` - everything is visible in the
page source. The framework-injected `Lux.csrf` (from `core.js`) lives under
`window.Lux`, not `window.app`.

## API

### Class-level (JS bundler)

| call | notes |
|------|-------|
| `Lux.browser.register(name, file:)` | path is relative to `Lux.fw_root` unless absolute |
| `Lux.browser.client_js(*names)` | composed JS string; no args = all modules |
| `Lux.browser.modules` | `[Symbol]` |
| `Lux.browser.registered?(name)` | Boolean |
| `Lux.browser` | the class itself (lets you say `Lux.browser.register ...`) |

### Instance-level (per-request)

| call | notes |
|------|-------|
| `lux.browser.header` | `Lux::Browser::Header` - `<head>` builder (also `lux.header`) |
| `lux.browser.window` | plain `Hash`, exported onto the client `window` |
| `lux.browser.window_script` | renders the `<script id="lux-state">...</script>` (emitted by `header.render`) |
| `lux.browser.bundle(*mods)` | composed client JS string (delegates to `client_js`) |
| `lux.browser.channel(name)` | SSE channel publisher (same as `Lux.channel`) |
| `lux.browser.publish(name, data)` | shorthand for `channel(name).push(data)`; from jobs use `Lux.channel(name).push(data)` |

## See also

* [`./channel/README.md`](./channel/README.md) - SSE channels, registers `:sse`
* [`../../../assets/lux/`](../../../assets/lux/) - JS module sources
