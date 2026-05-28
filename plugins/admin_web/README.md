# admin_web

Admin section for a Lux app. Mounts `/admin`, ships a controller + views
into the host app via `lux mount`, and bundles the PG-backed exception
logger that powers `/admin/plugins/exception_logger`.

## Setup

```ruby
# config/application.rb (or wherever plugins boot)
Lux.plugin :db
Lux.plugin :admin_web

# config/routes.rb (inside `routes do`)
plugin_routes   # auto-mounts /admin and every other plugin with routes.rb
```

Loading the plugin overrides `Lux::ErrorProxy.log` to `LuxException.add`,
so framework errors flowing through `Lux.error.log` are recorded automatically.

Then symlink the controller + views into the host app:

```sh
lux mount admin_web
```

That places:

```
app/controllers/admin_controller.rb
app/views/admin/root/index.haml
app/views/admin/plugins/exception_logger/{root,show}.haml
```

into the app root (as relative symlinks). Edit them in place - they're
your files now, the plugin just provides the starting point. `lux mount`
is idempotent.

## Exception Logger

PostgreSQL-backed exception logger. Exceptions are grouped by a
fingerprint made from class, message, and application backtrace, with
each occurrence stored separately in `LuxExceptionLog`.

The `root` and `show` pages under `app/views/admin/plugins/exception_logger/`
are pure templates - rendered by the host's `AdminController` via
`auto_find_template(nav.path)`. They look up their own data inline
(`LuxException.get_list`, `LuxException.get_exp(lux.params[:uid])`), so no
GET-side controller action is needed.

Resolving an exception is handled inline by the `show` view, not a
separate controller. Clicking Open/Resolved runs `Pjax.refresh('?toggle=<uid>')`,
which re-loads the page with a `?toggle=<uid>` GET param; the view flips
`is_resolved` and redirects back to the clean URL so a refresh or
back-button doesn't re-flip the state.

Open `/admin/plugins/exception_logger` to browse exceptions, filter by user
or class, inspect request logs, and mark exceptions as resolved.

### Manual Logging

```ruby
begin
  risky_call
rescue => err
  LuxException.add err
end
```

`LuxException.add` returns the grouped `LuxException` record. If the same
fingerprint already exists, it increments `times` and updates `last_at`.

### Query Helpers

```ruby
LuxException.get_list
LuxException.get_list klass: 'RuntimeError'
LuxException.get_users
LuxException.get_error_types
LuxException.get_exp uid
LuxException.size
```

Ignored classes in `LuxException::IGNORE` are excluded from the default
list and summary helpers unless you explicitly filter by class.

### Quick Summary

`LuxException.quick_summary` returns counts for day, week, and month
windows:

```ruby
LuxException.quick_summary
# {
#   day:   { new: 2, unresolved: 5, resolved: 1 },
#   week:  { new: 8, unresolved: 12, resolved: 4 },
#   month: { new: 21, unresolved: 18, resolved: 9 }
# }
```

Summary fields:

| Field | Meaning |
|-------|---------|
| `new` | Exceptions whose `first_at` is inside the window |
| `unresolved` | Unresolved exceptions with `last_at` inside the window |
| `resolved` | Resolved exceptions with `last_at` inside the window |

Existing records with `is_resolved` set to `nil` are treated as
unresolved.

### Models

#### `LuxException`

| Field | Type | Description |
|-------|------|-------------|
| `uid` | String | Fingerprint identifier |
| `klass` | String | Exception class name |
| `message` | Text | Exception message |
| `body` | Text | Backtrace |
| `times` | Integer | Number of grouped occurrences |
| `is_resolved` | Boolean | Resolution state |
| `first_at` | Time | First occurrence |
| `last_at` | Time | Most recent occurrence |

#### `LuxExceptionLog`

| Field | Type | Description |
|-------|------|-------------|
| `uid` | String | Matching `LuxException#uid` |
| `url` | Text | Request method and URL |
| `email` | String | Current user email, when available |
| `ip` | String | Request IP |
| `env` | Text | Sanitized request environment JSON |
| `created_at` | Time | Occurrence time |

## Layout

```
plugins/admin_web/
  loader.rb                                                   # overrides Lux::ErrorProxy.log
  lib/
    lux_exception.rb                                          # grouping + add/get/query API
    lux_exception_log.rb                                      # per-occurrence record
  mount/                                                      # symlinked into the host via `lux mount`
    app/
      controllers/admin_controller.rb
      views/admin/
        layout.haml
        root/index.haml
        plugins/exception_logger/{root,show}.haml             # rendered by host AdminController
        plugins/lux_jobs/{root,show}.haml                     # data from job_runner
        plugins/sys_logs/{root,show}.haml
  spec/
    exception_logger_admin_spec.rb                            # end-to-end flow
```

## See also

* [`../../lib/lux/plugin/README.md`](../../lib/lux/plugin/README.md) - plugin layout, `lux mount`
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `plugin_routes`, routing DSL
