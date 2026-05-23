# Lux::Browser - agent guide

Two roles in one class: a class-level JS bundler that composes
`window.Lux` and a per-request instance accumulator that ships app
state into `window.<root>` via a `<script>` tag.

## Canonical example

```ruby
# CLASS-LEVEL: register JS modules at boot, get the composed bundle.
Lux::Browser.register :sse, file: 'assets/lux/sse.js'
Lux::Browser.client(:sse)        # JS string served at /lux/sse.js
Lux::Browser.client              # all modules; served at /lux/client.js

# INSTANCE-LEVEL: ship per-request state to the page.
# Chain setters; intermediate nodes auto-vivify.
lux.browser.app.config.host    = Lux.config.host
lux.browser.app.config.locale  = lux.locale
lux.browser.app.data.user      = lux.user&.to_h
lux.browser.app.data.user.foo  = 'bar'         # deep chain ok

# Bracket form is equivalent at any depth:
lux.browser.app.config[:foo]   = 123

# Emit in the layout head:
#   != lux.browser.script_tag
# ->
#   <script id="lux-state">
#     window.app ||= {};
#     window.app.config = {"host":"...","locale":"en","foo":123};
#     window.app.data = {"user":{...,"foo":"bar"}};
#   </script>
```

## Rules

* **Reserved path.** `/lux/*` is intercepted in `Application#render_base`
  before routes; apps must not mount under `/lux/`.
* **Class methods are global.** Module registration is process-wide
  state. Call at framework / plugin load time, not from a request.
* **Instance is per-request.** `lux.browser` is memoised on
  `Lux.current`. Each request gets a fresh accumulator.
* **Emit rule:**
  * level-1 keys (`window.app`, `window.api`) → `||= {}` bootstrap
  * level-2 keys (`window.app.config`, ...) → atomic JSON assignment
    of the entire subtree
  * deeper chains collapse into the level-2 JSON
  * empty state still emits the bootstrap so pjax has a target
* **Pjax granularity** is the level-2 bucket. Group state into buckets
  that ship as a unit; partial within-bucket merges are not supported.
* **`</` is escaped to `<\/`** in string values so payloads can't break
  out of the `<script>` tag.

## Don't

* Don't ship secrets via `lux.browser` - everything is visible in HTML
  source.
* Don't put module-specific logic in `Lux::Browser` itself. The class
  is a dumb composer; each module owns its JS source under `assets/lux/`.
* Don't register modules from a request handler - registration is
  process-wide. Boot-time only.
* Don't reach for `/lux/*` mount routing from app code.
* Don't pjax-merge within a level-2 bucket - the framework re-renders
  the whole bucket atomically. Either ship as one unit or split into
  multiple level-2 keys.

## See also

* [`README.md`](./README.md) - human-facing API reference
* [`./channel/AGENTS.md`](./channel/AGENTS.md) - the SSE module registers via `Lux::Browser`
* [`../response/AGENTS.md`](../response/AGENTS.md) - `response.sse` consumes channels
