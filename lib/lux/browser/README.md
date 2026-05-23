# Lux::Browser

Two roles in one class:

1. **Class-level** - server-side composer for the `window.Lux` client
   surface. Subsystems register JS modules; the composed bundle is served
   at `/lux/*.js` (a reserved framework path).
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
Lux.browser.client                                        # all modules, core first
Lux.browser.client(:sse)                                  # core + sse only
Lux.browser.client(:sse, :api)                            # core + listed

# Served URLs (intercepted before route resolution; /lux/* is reserved):
#   /lux/client.js                  -> all registered modules
#   /lux/client.js?modules=sse,api  -> just those
#   /lux/<name>.js                  -> core + that one (404 if unknown)

# --- INSTANCE-LEVEL: per-request state (controller / before-filter) ---

lux.browser.app.config.host    = Lux.config.host
lux.browser.app.config.locale  = lux.locale
lux.browser.app.data.user      = lux.user&.to_h
lux.browser.app.data.user.foo  = 'bar'                    # deep chain ok
lux.browser.app.config[:flag]  = true                     # bracket form
lux.browser.api.url            = '/api'                   # multiple top-level namespaces

# Read-back / debug:
lux.browser.app.config.host                               # "..."
lux.browser.to_h                                          # full nested hash

# --- EMIT in the layout head (Haml example) ---
#   != lux.browser.script_tag
# ->
#   <script id="lux-state">
#     window.app ||= {};
#     window.app.config = {"host":"...","locale":"en","flag":true};
#     window.app.data = {"user":{...,"foo":"bar"}};
#     window.api ||= {};
#     window.api.url = "/api";
#   </script>
```

## Emit rule

* **Level 1** (root namespaces: `window.app`, `window.api`) - `||= {}`
  bootstrap so pjax-driven re-renders preserve untouched buckets.
* **Level 2** (`window.app.config`, `window.app.data`, ...) - atomic
  JSON assignment of the entire subtree below the level-2 key.
* **Deep chains** collapse into the level-2 JSON.
* **Empty state** still emits `<script id="lux-state">window.<ns> ||= {};</script>`
  so pjax has a stable target. Default `ns` is `app`; override via
  `Lux.config.browser_namespace`.
* **`</` in string values is escaped to `<\/`** so the payload can't
  break out of the surrounding `<script>` tag.

## Pjax granularity

Updates are atomic at the level-2 bucket. If a new page sets
`window.app.config`, an untouched `window.app.data` survives. Inside a
bucket it's a full replace - no per-key diff. Group state into level-2
buckets that ship as a unit.

## Security

Don't ship secrets via `lux.browser` - everything you set is visible in
the page source. The framework-injected `Lux.csrf` (from `core.js`)
lives under `window.Lux`, not `window.app`.

## API

### Class-level (JS bundler)

| call | notes |
|------|-------|
| `Lux.browser.register(name, file:)` | path is relative to `Lux.fw_root` unless absolute |
| `Lux.browser.client(*names)` | composed JS string; no args = all modules |
| `Lux.browser.modules` | `[Symbol]` |
| `Lux.browser.registered?(name)` | Boolean |
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

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`./channel/README.md`](./channel/README.md) - SSE channels, registers `:sse`
* [`../../../assets/lux/`](../../../assets/lux/) - JS module sources
