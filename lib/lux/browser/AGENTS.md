# Lux::Browser - agent guide

Server-side composer for `window.Lux` (client-side framework surface).
**Subsystems contribute JS modules via `Lux::Browser.register`; the
framework serves the composed bundle at `/lux/*.js`.**

## Canonical example

```ruby
# In a subsystem that ships a client module:
Lux::Browser.register :sse, file: 'assets/lux/sse.js'

# Anywhere on the server, get the composed JS string:
Lux::Browser.client            # core + every registered module
Lux::Browser.client(:sse)      # core + just :sse
Lux::Browser.client(:sse, :api)

# In an HTML template:
#   <script src="/lux/client.js"></script>
#   <script>Lux.sse.on('x', fn); Lux.sse.connect('/stream')</script>
```

## Rules

* **Reserved namespace.** `/lux/*` is intercepted in `Application#render_base`
  before route resolution. Apps must not mount routes under `/lux/`.
* **`:core` always prepended.** It bootstraps `window.Lux`, injects the
  per-request state (`Lux.csrf`, `Lux.config`), and adds `Lux.fetch`.
* **Module files are ERB-rendered.** Use `<%= ... %>` to embed server
  values; the binding has access to `Lux.current` and `Lux.config`.
* **Registration happens at load time.** Each subsystem registers in its
  own file (e.g. `lib/lux/channel/channel.rb` registers `:sse`). Do not
  register from inside a request.
* **Path resolution:** non-absolute `file:` paths are expanded against
  `Lux.fw_root`. Apps adding their own modules pass an absolute path.
* **No caching by default.** Bundle carries the caller's CSRF token, so
  response headers are `private, no-cache, no-store`.

## Don't

* Don't put module-specific logic in `Lux::Browser` itself. The composer
  is dumb on purpose; each module owns its JS source under `assets/lux/`.
* Don't register modules from a request handler - registration is global
  state. Register at framework / plugin load time.
* Don't reach for `/lux/*` mount routing from app code. The framework
  owns that prefix entirely.
* Don't add modules that touch the DOM beyond minimal helpers. `window.Lux`
  is the framework surface, not a UI library.

## See also

* [`README.md`](./README.md) - human-facing API reference
* [`../channel/AGENTS.md`](../channel/AGENTS.md) - the SSE module registers via `Lux::Browser`
* [`../response/AGENTS.md`](../response/AGENTS.md) - `response.sse` consumes channels
