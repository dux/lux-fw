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
LuxEventLog.log ['page_view', 'mobile'], path: '/pricing', referrer: 'google.com'
LuxEventLog.log :user_login
LuxEventLog.log [:api_call, :v2], path: 'GET /users', ms: 152, status: 200

# fast path: raw INSERT, no model/validations/hooks; returns the generated ref
LuxEventLog.add tags: [:api, :v2], data: { path: 'GET /users', ms: 152 }

LuxEventLog.where_all(['page_view', 'mobile']).count  # AND tag match, uses GIN index
LuxEventLog.where_any('mobile').count                 # OR tag match
LuxEventLog.all_tags(limit: 20)                       # top tags with counts

# funnel: per-step counts for an ordered tag list
# unique: 'user' counts distinct data->>'user' values (actor key in data);
# unique: true counts distinct whole data values
LuxEventLog.funnel [:visit, :signup, :purchase], since: 7.days.ago, unique: 'user'
# => [{ tag: 'visit', count: 120, pct: 100.0, step_pct: nil },
#     { tag: 'signup', count: 30, pct: 25.0, step_pct: 25.0 }, ...]
```

## Admin

* `/admin/plugins/event_log` - paginated list; day presets or an explicit from/to date window, tag filters.
* `/admin/plugins/event_log/funnel?tags=visit,signup,purchase&unique=user` - funnel view over an ordered tag list, with the same time controls and an optional "unique by" data key (empty = raw event counts).
  The URL fully encodes the funnel, so a bookmark acts as a saved funnel.

### Saved views

Every admin page keeps its full state in the URL, so views/searches/funnels are saved as name -> path records in the `lux_event_log_views` table (regular, durable table).
"Save view" / "Save funnel" prompts for a name and stores the current URL via `?save_as=<name>`; saving under an existing name replaces it; the x badge link (`?forget=<name>`) deletes.
Saved views show as badges on both pages, with the active one highlighted.

## Table

| column     | type                |
|------------|---------------------|
| ref        | varchar(20) PK      |
| tags       | text[], GIN index   |
| data       | jsonb, default `{}` |
| created_at | timestamp, index    |

The table is UNLOGGED: inserts skip the write-ahead log (much faster, no WAL bloat), but the table is truncated after a PG crash and is not replicated to standbys.
Use it for loss-tolerant event data only.

## Layout

```
plugins/event_log/
  loader.rb                  # requires lib/*
  lib/
    lux_event_log.rb         # model + schema + log/add/funnel API
    lux_event_log_view.rb    # saved views (name -> url)
  mount/app/views/admin/plugins/event_log/
    .yaml                    # admin nav registration
    root.haml                # event list
    funnel.haml              # funnel over an ordered tag list
```
