# Lux.plugin :web_common

The shared web layer for a Lux app, bundled as one plugin: asset URLs, html
builders, the exception writer (dboss reads its file) and the `/dev` pages. Each app owns its `/admin` area (controller, layout, assets).

```yaml
# config/config.yaml
default:
  plugins:
    - db
    - authcog
    - web_common
```

`web_common` builds on `db` (the legacy exception viewer needs Sequel models)
and on `authcog` (`ApplicationApi` reads the signed-in user through
`UserSession`). It does not pull `authcog` in; list both. The exception writer
itself needs neither.

## What's inside

| Area | Provides | Loaded from |
|------|----------|-------------|
| assets  | `CdnAsset` (manifest/CDN asset URLs) + `ApplicationHelper` template helpers (`request`, `response`) | `load/assets/` |
| html    | form / input / table builders plus `HtmlMenu`, `HtmlHelper.paginate`, `HtmlFilter`, timezone helpers | `load/html/` |
| api     | `ApplicationApi` (mounted at `/api`), `ModelApi` (generated CRUD), `SchemaMap` | `load/lib/` |
| exceptions | legacy PG-backed exception logger (`LuxException` / `LuxExceptionLog`, `LuxExceptionsApi`) | `load/lib/` |
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
    map 'dev',     'dev#auto'        # dev pages (ship in mount/)
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

The legacy PG models (`LuxException` / `LuxExceptionLog`) and the
`/api/lux_exceptions/toggle` API stay in the plugin but are no longer the hook
target.

Server logs are read in dboss.

## Api() notifications

`Api()` / `$.api` is silent on success by default, so never write `.silent()`.
Opt in only for direct user actions (click, submit, drag): `.info()` shows a toast, `.topInfo()` flashes the top progress bar.
A server error response always shows a red toast, even on a silent call - pass `.error(fn)` only to replace it.
The full chain list is at the top of `dollar/dollar_api.js`.

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
  hammer/              # assets:* pipeline, docker:* tasks, `lux generate`
  load/
    assets/  html/{form,input,table,...}
    lib/                 # ApplicationApi, ModelApi, SchemaMap, ExceptionWriter, legacy LuxException(s)
  assets/js/           # browser sources ($ shim, sys-* fez, lib), imported as @web-common/js/...
  mount/               # /dev controller and views, lux_models.js.rb generator (Lux::Root overlay)
  spec/                # exception writer/hook specs, HtmlForm/HtmlInput/HtmlTable
```

## Assets

The asset pipeline (`lux assets:generate|build|deploy`) ships with this plugin in
`hammer/assets_hammer.rb`, so only apps that list `web_common` get it.

* `lux assets:build` - runs the `app/assets` generators, then the app's
  `assets:compile`, the [`favicon`](../favicon/README.md) touch icon when that
  plugin is loaded, then writes `public/manifest.json` (`app.css` -> `app.1a2b3c4d.css`).
* `lux assets:deploy` - `build`, then, when production sets `cdn_root`,
  `lux assets:upload ./public/assets/<file> assets/<hashed>` per manifest entry.
* `lux pack` ships `public/assets` and `public/manifest.json`. In production
  `CdnAsset.url` maps names through the manifest to `cdn_root/assets/<hashed>`;
  without `cdn_root` it serves `/assets/<name>?<deploy id>`. `CdnAsset.path`
  returns that url without the tag (nil when the asset is not built).

Generators: `app/assets/<name>.<ext>.rb` is committed and evaluated with the app loaded.
The returned string is written to `app/assets/<name>.tmp.<ext>` with an autogenerated banner.
Apps gitignore `*.tmp.*` and import the output from their bundle (`import './lux_models.tmp.js'`).
A plugin mount can ship a generator; an app file of the same name shadows it.
`lux s` runs the generators before the Procfile, so the asset watcher finds them on its first build.
A watcher started some other way (a dboss `js_dev` script) runs `lux assets:generate` before `rollup -cw`.
This plugin ships `lux_models.js.rb` (see [Model handles](#model-handles)).

Two app contracts live in `lib/tasks`; lux core ships stubs.
`lux assets:compile` builds `app/assets` into `public/assets` with the app's own toolchain; the stub dies.
`lux assets:upload LOCAL_PATH REMOTE_PATH` is fulfilled by every app with a `cdn_root`; the stub uploads nothing.
`REMOTE_PATH` is relative to `cdn_root`; a trailing `/` makes it a folder.
How the app authenticates is its own business. Failure must exit non-zero:

```ruby
namespace :assets do
  task :compile do
    desc 'Build app/assets into public/assets (lux contract)'
    proc { system({ 'NODE_PRESERVE_SYMLINKS' => '1' }, 'bun run rollup -c') || Lux.shell.die('asset compile failed') }
  end

  task :upload do
    desc 'Upload LOCAL_PATH to REMOTE_PATH on the CDN (lux contract)'
    needs :app
    proc do |opts|
      local, remote = opts[:args]
      remote += File.basename(local) if remote.end_with?('/')
      MyStorage.put(local, remote) || Lux.shell.die("upload failed: #{local}")
    end
  end
end
```

## Model handles

`app.m.<model>(ref)` calls a model API from the browser without the page exporting the record first.
`ModelApi.client_index` lists every `ModelApi` subclass: model name, API path and action names.
`lux_models.js.rb` writes it to `app/assets/lux_models.tmp.js` as `Lux.models`.
`dollar_api.js` builds the handles from it on first access of `app.m`.

```js
app.m.user(ref).update({ name: 'x' }).done(fn)   // member actions are methods on the handle
app.m.user(record).destroy().follow('/users')    // anything with .ref works too
app.m.user.create({ email: 'a@b.c' }).info()     // collection actions sit on the factory
app.m.work_order(ref).show()                     // key = model name, snake_case
Lux.models                                       // { user: { path, member: [...], collection: [...] } }
```

* Every call returns the `Api()` chain, so the [Api() notifications](#api-notifications) rules apply.
* Paths come from the server, so irregular plurals and singular API names (`EmployeeApi` -> `/api/employee`) just work.
* An unknown model or action is a `TypeError`, not a 404; a missing ref throws.
* `undocumented` actions are not on the index.
* `window.app.m` is reserved: it has no setter, so exporting `window[:app][:m]` fails loudly.
* A new model API shows up after the next `lux s` or `lux assets:build`.

## See also

* [`../../lib/lux/plugin/README.md`](../../lib/lux/plugin/README.md) - plugin layout, mount overlays
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `plugin_routes`, routing DSL
