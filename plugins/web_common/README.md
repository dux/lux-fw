# Lux.plugin :web_common

The shared web layer for a Lux app, bundled as one plugin. It folds
together six formerly separate plugins - `assets`, `favicon`, `header`,
`html`, `authcog`, `admin_web` - so an app lists a single entry:

```yaml
# config/config.yaml
default:
  plugins:
    - db
    - web_common
    - oauth
```

`web_common` builds on `db` (the exception logger needs Sequel models), so
list it after `db`.

## What's inside

| Area | Provides | Loaded from |
|------|----------|-------------|
| assets  | `CdnAsset` (manifest/CDN asset URLs) + `ApplicationHelper` template helpers (`svelte`, `request`, `response`) | `load/assets/` |
| favicon | `Lux::Favicon.head` `<link>` builder + `routes.rb` serving `public/favicon.svg` for legacy `.ico` / `apple-touch-icon` polling | `load/favicon/`, `routes.rb` |
| header  | `lux.header` - per-request `<head>` builder (title, description, og/twitter meta, canonical, robots) | `load/header/` |
| html    | form / input / table builders plus `HtmlMenu`, `HtmlHelper.paginate`, `HtmlFilter`, timezone helpers | `load/html/` |
| authcog | `AuthcogController` - central-auth login + hash-callback landing | `lib/authcog_controller.rb` |
| admin_web | PG-backed exception logger (`LuxException` / `LuxExceptionLog`) and a mountable `/admin` viewer | `lib/`, `mount/` |

The detailed per-builder docs live next to the code:

* `load/html/form/README.md`
* `load/html/input/README.md`
* `load/html/table/README.md`

## Wiring

### Routes

```ruby
Lux do
  routes do
    favicon './public/favicon.svg'   # framework DSL for /favicon.svg itself

    map 'authcog', 'authcog#call'    # central-auth login + landing
    map 'admin',   'admin#call'      # admin viewer (after `lux mount web_common`)

    plugin_routes                    # picks up web_common/routes.rb (favicon polling)
  end
end
```

`plugin_route :web_common` / `plugin_routes` evaluate `routes.rb`, which only
declares the legacy favicon-polling handlers; everything else is wired
explicitly by the app, as above.

### Header

```ruby
lux.header.title       'My page'
lux.header.description 'short summary'
lux.header.canonical   'https://example.com/page'
```

```haml
%head
  = lux.header.render do |page|
    != Lux::Favicon.head
    = asset 'main.css'
```

### Exception logger

Loading the plugin overrides `Lux::ErrorProxy.log` so framework errors
flowing through `Lux.error.log` are recorded in `lux_exceptions`. The
override is a no-op until the table exists, so an app can adopt
`web_common` before running `lux db:am`; the first auto-migrate creates
`lux_exceptions` + `lux_exception_logs` from the model schemas.

Mount the `/admin` controller + views into the host:

```sh
lux mount web_common
```

Then browse `/admin/plugins/exception_logger`. See the query/summary API on
`LuxException` (`get_list`, `get_exp`, `quick_summary`, ...) in
`lib/lux_exception.rb`.

## Layout

```
plugins/web_common/
  loader.rb            # authcog + exception-logger wiring, ErrorProxy.log hook
  routes.rb            # legacy favicon / apple-touch-icon polling
  Hammerfile           # `lux assets:auto` compiler
  load/
    assets/  favicon/  header/  html/{form,input,table,...}
  lib/
    authcog_controller.rb
    lux_exception.rb  lux_exception_log.rb
  mount/               # /admin controller + views (symlinked by `lux mount`)
  seeds/               # lux_exceptions seed data
  spec/                # exception logger end-to-end flow

```

## See also

* [`../../lib/lux/plugin/README.md`](../../lib/lux/plugin/README.md) - plugin layout, `lux mount`
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `plugin_routes`, routing DSL
