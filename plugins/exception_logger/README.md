# LuxException - Exception Logger Plugin

PostgreSQL-backed exception logger for Lux apps. Exceptions are grouped by a
fingerprint made from class, message, and application backtrace, with each
occurrence stored separately in `LuxExceptionLog`.

## Setup

Load the database plugin first, then load the exception logger:

```ruby
Lux.plugin :db
Lux.plugin :exception_logger
```

The loader wires `Lux.config.error_logger` to `LuxException.add`, so framework
errors are recorded automatically after the plugin is loaded.

## Web Viewer

Mount the Sinatra viewer in your app routes:

```ruby
LuxExceptionWeb.password = ENV['LUX_EXCEPTION_PASSWORD']

Lux.app do
  routes do
    mount LuxExceptionWeb, at: '/admin/sys-errors'
  end
end
```

Open `/admin/sys-errors` to browse exceptions, filter by user or class, inspect
request logs, and mark exceptions as resolved.

## Manual Logging

You can also record an exception directly:

```ruby
begin
  risky_call
rescue => err
  LuxException.add err
end
```

`LuxException.add` returns the grouped `LuxException` record. If the same
fingerprint already exists, it increments `times` and updates `last_at`.

## Query Helpers

```ruby
LuxException.get_list
LuxException.get_list klass: 'RuntimeError'
LuxException.get_users
LuxException.get_error_types
LuxException.get_exp uid
LuxException.size
```

Ignored classes in `LuxException::IGNORE` are excluded from the default list and
summary helpers unless you explicitly filter by class.

## Quick Summary

`LuxException.quick_summary` returns counts for day, week, and month windows:

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

Existing records with `is_resolved` set to `nil` are treated as unresolved.

## Models

### `LuxException`

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

### `LuxExceptionLog`

| Field | Type | Description |
|-------|------|-------------|
| `uid` | String | Matching `LuxException#uid` |
| `url` | Text | Request method and URL |
| `email` | String | Current user email, when available |
| `ip` | String | Request IP |
| `env` | Text | Sanitized request environment JSON |
| `created_at` | Time | Occurrence time |
