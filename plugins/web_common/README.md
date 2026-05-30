# Lux.plugin :web_common

The shared web layer for a Lux app, bundled as one plugin. It folds
together formerly separate plugins - `assets`, `favicon`, `html`,
`authcog`, `admin_web` - so an app lists a single entry:

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
| favicon | `favicon '/icon.svg'` routing DSL - serves the icon at `/favicon.ico` and injects web + `apple-touch-icon` `<link>` tags into `<head>` | `load/favicon.rb` |
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
    map 'authcog', 'authcog#call'    # central-auth login + landing
    map 'admin',   'admin#call'      # admin viewer (after `lux mount web_common`)
  end
end
```

Everything is wired explicitly by the app, as above.

### Exception logger

Loading the plugin defines `Lux::ErrorProxy.log_custom` so framework errors
flowing through `Lux.error.log` are recorded in `lux_exceptions` after the
framework has handled duplicate suppression, screen logging, and error-file
logging. If the exception tables are not migrated yet, the framework logs the
custom hook failure without masking the original error; the first auto-migrate
creates `lux_exceptions` + `lux_exception_logs` from the model schemas.

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
  loader.rb            # authcog + exception-logger wiring, ErrorProxy.log_custom hook
  Hammerfile           # `lux assets:auto` compiler
  load/
    favicon.rb           # `favicon` routing DSL
    assets/  html/{form,input,table,...}
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
