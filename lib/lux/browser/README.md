# Lux::Browser

Two roles in one class:

1. **Class-level** - server-side composer for the `window.Lux` client
   surface. Subsystems register JS modules; the composed bundle is served
   at `/_lux_/*.js` (a reserved framework path).
2. **Instance-level** - per-request state accumulator, accessed via
   `lux.browser`. Chain-set arbitrary nested keys; emit as a `<script>`
   tag in the page head. Lands as `window.<root>` (separate namespace
   from `window.Lux` on purpose).

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

# --- INSTANCE-LEVEL: per-request state (controller / before-filter) ---

lux.browser.app.cfg.host       = Lux.config.host
lux.browser.app.cfg.locale     = lux.locale
lux.browser.app.current.user   = lux.user&.to_h
lux.browser.app.current.user.foo = 'bar'                  # deep chain ok
lux.browser.app.cfg[:flag]     = true                     # bracket form
lux.browser.app.page.title     = 'Home'                   # cleared on next nav
lux.browser.api.url            = '/api'                   # extra top-level namespace

# Read-back / debug:
lux.browser.app.cfg.host                                  # "..."
lux.browser.to_h                                          # full nested hash

# --- EMIT in the layout head (Haml example) ---
#   != lux.browser.script_tag
# ->
#   <script id="lux-state">
#     window.app ||= {};
#     window.app.cfg = {"host":"...","locale":"en","flag":true};
#     window.app.current = {"user":{...,"foo":"bar"}};
#     window.app.page = {"title":"Home"};
#     window.api ||= {};
#     window.api.url = "/api";
#   </script>
```

The three `app` buckets (`cfg` / `current` / `page`) are the canonical home
for all server-injected client state; custom function globals live under
`app.fn`. See [STATE.md](./STATE.md).

## Emit rule

* **Level 1** (root namespaces: `window.app`, `window.api`) - `||= {}`
  bootstrap so pjax-driven re-renders preserve untouched buckets.
* **Level 2** (`window.app.cfg`, `window.app.current`, ...) - atomic
  JSON assignment of the entire subtree below the level-2 key.
* **Deep chains** collapse into the level-2 JSON.
* **Default namespace** (`Lux.config.browser_namespace`, default `app`) is
  always emitted, and its volatile `app.page` bucket is always emitted too
  (as `{}` when unset) so each navigation clears the prior page's payload.
* **`</` in string values is escaped to `<\/`** so the payload can't
  break out of the surrounding `<script>` tag.

## Pjax granularity

Updates are atomic at the level-2 bucket. If a new page sets
`window.app.cfg`, an untouched `window.app.current` survives. Inside a
bucket it's a full replace - no per-key diff. Group state into level-2
buckets that ship as a unit. `app.page` is the exception: it is reset on
every render, so it never carries state across navigations.

## Security

Don't ship secrets via `lux.browser` - everything you set is visible in
the page source. The framework-injected `Lux.csrf` (from `core.js`)
lives under `window.Lux`, not `window.app`.

## API

### Class-level (JS bundler)

| call | notes |
|------|-------|
| `Lux.browser.register(name, file:)` | path is relative to `Lux.fw_root` unless absolute |
| `Lux.browser.client_js(*names)` | composed JS string; no args = all modules |
| `Lux.browser.modules` | `[Symbol]` |
| `Lux.browser.registered?(name)` | Boolean |
| `Lux.browser.publish(channel, data)` | broadcast to SSE subscribers (`Lux.subscribe` on client) |
| `Lux.browser` | the class itself (lets you say `Lux.browser.register ...`) |

### Instance-level (per-request)

| call | notes |
|------|-------|
| `lux.browser.<root>.<key>...= value` | chained setter; auto-creates parents |
| `lux.browser.<root>.<key>[k] = value` | bracket setter at any depth |
| `lux.browser.<root>.<key>` | read; returns value or a fresh Node |
| `lux.browser.script_tag` | renders the `<script id="lux-state">...</script>` |
| `lux.browser.to_h` | deep-hash representation |

## See also

* [`./channel/README.md`](./channel/README.md) - SSE channels, registers `:sse`
* [`../../../assets/lux/`](../../../assets/lux/) - JS module sources
