# Lux::Browser

Server-side composer for the `window.Lux` client surface. Subsystems
register JS modules; the framework serves the composed bundle at
`/lux/*.js` with per-request state (csrf, locale, host) interpolated
through ERB.

The `/lux` URL path is reserved for framework-served assets and is
intercepted in `Lux::Application#render_base` before route resolution.

## Small example

```ruby
# A subsystem registers its client-side module on load.
Lux::Browser.register :sse, file: 'assets/lux/sse.js'

# Anywhere on the server you can get the composed bundle as a string.
Lux::Browser.client          # core + every registered module
Lux::Browser.client(:sse)    # core + sse
```

In a template:

```html
<script src="/lux/client.js"></script>
<script>
  Lux.sse.on('user:42', msg => inbox.update(msg))
  Lux.sse.connect('/stream')
</script>
```

## How it composes

* **`:core` is always first.** It sets up `window.Lux`, injects the
  per-request state (`Lux.csrf`, `Lux.config.host`, `Lux.config.locale`),
  and adds `Lux.fetch` (a CSRF+JSON-aware wrapper over `fetch`).
* Every other module is appended in the order requested.
* Each file is rendered through ERB, so module sources may use
  `<%= ... %>` to inject server values too.

## Served URLs

| URL                          | What it serves |
|------------------------------|----------------|
| `/lux/client.js`             | core + every registered module |
| `/lux/client.js?modules=sse` | core + just the listed modules |
| `/lux/<name>.js`             | core + just `<name>` (404 if unknown) |

Cache headers are `private, no-cache, no-store` because each request
carries the caller's CSRF token. If you want to cache, set up your own
asset pipeline and point at static copies of `assets/lux/*.js`.

## API

| call | returns | notes |
|------|---------|-------|
| `Lux::Browser.register(name, file:)` | nil | path is relative to `Lux.fw_root` unless absolute |
| `Lux::Browser.client(*names)` | String | composed bundle; empty args = all modules |
| `Lux::Browser.modules` | `[Symbol]` | registered names |
| `Lux::Browser.registered?(name)` | Boolean | |
| `Lux.browser` | `Lux::Browser` | shorthand |

## See also

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`../channel/README.md`](../channel/README.md) - pub/sub channels, registers `:sse`
* [`../../../assets/lux/`](../../../assets/lux/) - the JS module sources
