# Lux.plugin :event_log

Event log entries in an UNLOGGED PostgreSQL table, with an admin dashboard.

## Setup

```ruby
Lux.plugin :db
Lux.plugin :event_log
```

Then create the table and mount the admin interface:

```bash
lux db:am              # creates/syncs the lux_event_logs table
lux mount event_log    # symlinks the admin dashboard into the app
```

## Usage

```ruby
LuxEventLog.log ['page_view', 'mobile'], '/pricing', { referrer: 'google.com' }
LuxEventLog.log :user_login
LuxEventLog.log [:api_call, :v2], 'GET /users', { ms: 152, status: 200 }

# fast path: raw INSERT, no model/validations/hooks; truncates data to 200
# chars instead of raising; returns the generated ref
LuxEventLog.add tags: [:api, :v2], data: 'GET /users', json_data: { ms: 152 }

LuxEventLog.where_all(['page_view', 'mobile']).count  # AND tag match, uses GIN index
LuxEventLog.where_any('mobile').count                 # OR tag match
LuxEventLog.all_tags(limit: 20)                       # top tags with counts
```

Admin dashboard: `/admin/plugins/event_log` (paginated list, date range + tag filters).

## Table

| column     | type                   |
|------------|------------------------|
| ref        | varchar(20) PK         |
| tags       | text[], GIN index      |
| data       | varchar(200), optional |
| json_data  | jsonb, default `{}`    |
| created_at | timestamp, index       |

The table is UNLOGGED: inserts skip the write-ahead log (much faster, no WAL bloat), but the table is truncated after a PG crash and is not replicated to standbys.
Use it for loss-tolerant event data only.

## Layout

```
plugins/event_log/
  loader.rb                  # requires lib/lux_event_log
  lib/
    lux_event_log.rb         # model + schema + log API
  mount/app/views/admin/plugins/event_log/
    .yaml                    # admin nav registration
    root.haml                # admin dashboard
```
