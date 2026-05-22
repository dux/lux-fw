# admin_web

Skeleton admin section for a Lux app. Mounts `/admin` and ships a
controller + view into the host app via `lux mount`. Intended as the base
other admin plugins (exception_logger, job_runner, ...) hang off of.

## Setup

```ruby
# config/application.rb (or wherever plugins boot)
Lux.plugin :admin_web

# config/routes.rb (inside `routes do`)
plugin_routes   # auto-mounts /admin and every other plugin with routes.rb
```

Then symlink the controller + view into the host app:

```sh
lux mount admin_web
```

That places:

```
app/controllers/admin/root_controller.rb
app/views/admin/root/index.haml
```

into the app root (as relative symlinks). Edit them in place - they're
your files now, the plugin just provides the starting point. `lux mount`
is idempotent.

## Layout

```
plugins/admin_web/
  loader.rb                                 # no-op boot hook
  routes.rb                                 # map 'admin' do; root 'admin/root'; end
  mount/
    app/
      controllers/admin/root_controller.rb  # symlinks into the host
      views/admin/root/index.haml           # symlinks into the host
```

## See also

* [`../../lib/lux/plugin/README.md`](../../lib/lux/plugin/README.md) - plugin layout, `lux mount`
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `plugin_routes`, routing DSL
