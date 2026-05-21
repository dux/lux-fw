# Lux::Db - agent guide

Multi-DB Sequel connection registry. Connections are lazy on first
access; eager on `Lux.plugin :db` boot.

## Canonical example

```ruby
# config.yaml - hash form for named DBs
# db:
#   main: postgresql://localhost/myapp
#   log:  postgresql://localhost/myapp_log

Lux.db                  # :main
Lux.db(:log)            # :log
DB[:users]              # dataset on :main (via lazy proxy)

Lux::Db.connections     # all active connections
Lux::Db.configured_names
Lux::Db.url_for(:log)
Lux::Db.disconnect_all  # close all pools
```

## Rules

* **`DB` constant** is a lazy proxy to `Lux.db(:main)`. Don't replace
  it; use `Lux.db(:name)` to reach others.
* **Config key is `db:`** (NOT `dbs:`). Accepts a string (single main DB)
  or a hash (named DBs).
* **ENV overrides:** `DB_MAIN`, `DB_LOG`, etc. `DB_URL` as fallback for
  `:main`. Then `Lux.config[:db_url]`.
* **Boot behavior:** `Lux.plugin :db` runs `loader.rb` which calls
  `Lux::Db.boot!`. All configured DBs connect eagerly; errors surface
  here. The plugin then auto-requires `plugins/db/load/*.rb` for Sequel
  model extensions.
* **Multi-DB pattern:** put writes/reads on `:main`, slow logs/analytics
  on `:log`. Models default to `:main`; switch on a per-model basis with
  `Sequel::Model.set_dataset(Lux.db(:log)[:events])`.
* **Test DBs:** suffix `_test`. `rake db:create:test` drops + copies
  schema from main.
* **Models** use `ref` (string ULID) as primary key, not integer `id`.
  See `plugins/db/AGENTS.md`.

## Don't

* Reach into `CONNECTIONS` directly - go through `Lux.db(:name)`.
* Run destructive rake tasks in production - they're blocked, but don't
  rely on that.
* Mix `Lux.config[:db_url]` with `db:` config - the resolution order is
  documented but confusing; pick one.

## See also

* [`plugins/db/AGENTS.md`](../../../plugins/db/AGENTS.md) - Sequel model
  extensions, schema/migrations, `link` associations
* [`Lux::Schema` AGENTS](../schema/AGENTS.md)
