# Lux.plugin :web_common

The shared web layer for a Lux app, bundled as one plugin: asset URLs, html
builders, the exception writer (dboss reads its file) and the `/dev` pages. Each app owns its `/admin` area (router, layout, assets).

```yaml
# config/config.yaml
default:
  plugins:
    - db
    - authcog
    - web_common
```

`web_common` builds on `db` (`ModelApi` and the html builders work on Sequel models)
and on `authcog` (`ApplicationApi` reads the signed-in user through
`UserSession`). It does not pull `authcog` in; list both. The exception writer
itself needs neither.

## What's inside

| Area | Provides | Loaded from |
|------|----------|-------------|
| assets  | `CdnAsset` (manifest/CDN asset URLs) + `HtmlHelper` template helpers (`response`); plugin helpers live in `HtmlHelper` so the app's `ApplicationHelper` overrides them | `load/assets/` |
| html    | form / input / table builders plus `HtmlMenu`, `HtmlHelper.paginate` | `load/html/` |
| api     | `ApplicationApi` (mounted at `/api`; non-`unsafe` endpoints answer 401 without a user), `ModelApi` (generated CRUD) | `load/lib/` |
| routes  | router helpers for `Lux.router` blocks: `server_info` (`/lux` diagnostics via `ServerInfo`, dev or admin) | `load/lib/web_common_routes.rb`, `load/lib/server_info.rb` |
| dev     | `/dev` pages: index of dev pages (an app `app/views/dev/root.haml` replaces it), schema map (`SchemaMap`), login-as; dev env only | `mount/app/routers/dev_router.rb`, `mount/app/views/dev/`, `load/lib/schema_map.rb` |
| generate | `lux generate <object>`: model, api, exporter, policy and cell templates (`m`); an app `config/templates/` dir replaces them | `hammer/generate_hammer.rb`, `hammer/generate/` |

Sign-in (`AuthcogRouter`, `UserSession`) is the separate
[`authcog`](../authcog/README.md) plugin.

The detailed per-builder docs live next to the code:

* `load/html/form/README.md`
* `load/html/input/README.md`
* `load/html/table/README.md`

## Wiring

### Routes

```ruby
Lux do
  route do
    map 'authcog', 'authcog#call'    # central-auth callback landing
    map 'dev',     'dev#auto'        # dev pages (ship in mount/)
  end
end
```

Everything is wired explicitly by the app, as above.
The plugin also relies on these app contracts:

* `FrontendRouter` must exist (`DevRouter` subclasses it).
* Models answer `api_path(action)` for `form @model`.
* The `/lux` diagnostics need a `server_info` line inside `route do`.
* The app ships every browser global the html builders emit; the plugin ships no JS.
  `form` renders `/api/` actions as `<api-form>`, table, form and paginate helpers emit `Api(...)`, `Dialog.*`, `$(...)` and `data-key` shortcuts.

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
`headers`, `request_id` (the `X-Request-Id` / generated id) and `ts` (UTC RFC3339). `user` falls back to the signed-in user's
email (`Lux.ctx.user.email`); `ip`, `method`, `url` and `headers` come from
the current request, and `headers` keeps only `ExceptionWriter::HEADERS`
(User-Agent, Referer, Accept-Language, ...), never Cookie or Authorization.
`tags` and `description` are absent unless passed. Appends are flocked, so
concurrent processes never interleave records.
Expected HTTP errors (`Lux::Error` below 500, API, policy and validation errors) are skipped.

Server logs are read in dboss.

## Layout

```
plugins/web_common/
  loader.rb            # Lux.error.on_log reporter -> ExceptionWriter
  hammer/              # assets:* pipeline, docker:* tasks, `lux generate`
  load/
    assets/  html/{form,input,table,...}
    lib/                 # ApplicationApi, ModelApi, SchemaMap, ExceptionWriter
  mount/               # /dev router and views (Lux::Root overlay)
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
Apps gitignore `*.tmp.*` and import the output from their bundle (`import './country_codes.tmp.js'`).
A plugin mount can ship a generator; an app file of the same name shadows it.
`lux s` runs the generators before the Procfile, so the asset watcher finds them on its first build.
A watcher started some other way (a dboss `js_dev` script) runs `lux assets:generate` before `rollup -cw`.

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

## See also

* [`../../lib/lux/plugin/README.md`](../../lib/lux/plugin/README.md) - plugin layout, mount overlays
* [`../../lib/lux/router/README.md`](../../lib/lux/router/README.md) - `plugin_routes`, routing DSL
