# Lux.plugin :web_common

The shared web layer for a Lux app, bundled as one plugin: asset URLs, the
favicon DSL, html builders, the exception writer (dboss reads its file) and the
`/admin` area.

```yaml
# config/config.yaml
default:
  plugins:
    - db
    - authcog
    - web_common
```

`web_common` builds on `db` (the legacy exception viewer needs Sequel models)
and on `authcog` (`ApplicationApi` and `/admin` read the signed-in user through
`UserSession`). It does not pull `authcog` in; list both. The exception writer
itself needs neither.

## What's inside

| Area | Provides | Loaded from |
|------|----------|-------------|
| assets  | `CdnAsset` (manifest/CDN asset URLs) + `ApplicationHelper` template helpers (`request`, `response`) | `load/assets/` |
| favicon | `favicon '/icon.svg'` routing DSL - serves the icon at `/favicon.ico` and injects web + `apple-touch-icon` `<link>` tags into `<head>` | `load/favicon.rb` |
| html    | form / input / table builders plus `HtmlMenu`, `HtmlHelper.paginate`, `HtmlFilter`, timezone helpers | `load/html/` |
| api     | `ApplicationApi` (mounted at `/api`), `ModelApi` (generated CRUD), `SchemaMap` | `load/lib/` |
| admin_web | PG-backed exception logger (`LuxException` / `LuxExceptionLog`, `LuxExceptionsApi`) and the `/admin` area | `load/lib/`, `mount/` |
| dev     | `/dev` pages: schema map, login-as | `mount/app/controllers/dev_controller.rb`, `mount/app/views/dev/` |

Sign-in (`AuthcogController`, `UserSession`) is the separate
[`authcog`](../authcog/README.md) plugin.

The detailed per-builder docs live next to the code:

* `load/html/form/README.md`
* `load/html/input/README.md`
* `load/html/table/README.md`

## Wiring

### Routes

```ruby
Lux do
  routes do
    map 'authcog', 'authcog#call'    # central-auth callback landing
    map 'admin',   'admin#call'      # admin viewer (ships in mount/)
  end
end
```

Everything is wired explicitly by the app, as above.

### Exception writer

Loading the plugin registers a `Lux.error.on_log` reporter so framework errors
flowing through `Lux.error.log` are written as compact JSON lines to
`<Lux.root>/log/app.exceptions.log` after the framework has handled duplicate
suppression, screen logging and error-file logging. dboss tails that file into
its per-app `exceptions` tables (one summary row per fingerprint, one count row
per UTC minute). A writer failure is logged by the hook and never masks the
original exception.

```ruby
ExceptionWriter.new(error).write
ExceptionWriter.new(error).write(user: user.ref, ip: '203.0.113.7',
                                tags: ['checkout'], description: 'Confirming an order')
```

Each line carries `uid` (SHA-256 of `[file, line, class]` from the first
application backtrace frame), `dump` (`error.full_message(highlight: false)`),
`message`, optional `user`, `ip`, `tags`, `description`, `method`, `url`,
`headers` and `ts` (UTC RFC3339). `user` falls back to the signed-in user's
email (`Lux.current.user.email`); `ip`, `method`, `url` and `headers` come from
the current request, and `headers` keeps only `ExceptionWriter::HEADERS`
(User-Agent, Referer, Accept-Language, ...), never Cookie or Authorization.
`tags` and `description` are absent unless passed. Appends are flocked, so
concurrent processes never interleave records.

The legacy PG models (`LuxException` / `LuxExceptionLog`), their `/admin` pages
and the `/api/lux_exceptions/toggle` API stay in the plugin but are no longer
the hook target; `LuxException` (`get_list`, `get_exp`, `quick_summary`, ...)
still backs the old viewer. The `/admin` controller and views ship in the
plugin's `mount/` tree and resolve through the `Lux::Root` overlay. The plugin's
`AdminController` requires `user.can.admin?`; an app that ships its own
`AdminController` owns that check.

Server logs are read in dboss, not in `/admin`.

## Browser API response event

`Api(...)` and `<api-form>` dispatch `api:response` on `document` after a successful HTTP response and before their completion callbacks.
The event detail is `{ path, response }`, containing the request path and parsed API envelope.
Apps can subscribe to update client caches before callbacks refresh or navigate the UI.

```js
document.addEventListener('api:response', ({ detail }) => {
  console.log(detail.path, detail.response.data)
})
```

## Layout

```
plugins/web_common/
  loader.rb            # Lux.error.on_log reporter -> ExceptionWriter
  hammer/              # docker:* tasks, `lux generate` (assets:* lives in lux-fw core)
  load/
    favicon.rb           # `favicon` routing DSL
    assets/  html/{form,input,table,...}
    lib/                 # ApplicationApi, ModelApi, SchemaMap, ExceptionWriter, legacy LuxException(s)
  mount/               # /admin + /dev controllers and views (Lux::Root overlay)
  demo/                # fake lux_exceptions for UI work; loaded by hand (see the file header)
  spec/                # exception writer/hook specs, legacy logger flow, HtmlForm/HtmlInput/HtmlTable
```

Asset pipeline (`lux assets:auto|build|upload|deploy`) ships with this plugin:
`hammer/assets_hammer.rb`, so only apps that list `web_common` get it, and
`lux s` runs `assets:auto` only when the app also has a `package.json`. Generators are `name.ext.rb` under
`app/assets/auto/<pack>/{js,css}/` - last returned string becomes
`name.tmp.ext` (gitignored) with an autogenerated banner. The `.rb` source
is hand-written as-is (no banner there).

## See also

* [`../../lib/lux/plugin/README.md`](../../lib/lux/plugin/README.md) - plugin layout, mount overlays
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `plugin_routes`, routing DSL
