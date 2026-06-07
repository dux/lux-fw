# Lux::Db

Sequel multi-DB connection management. Connections are lazy; on
`Lux.plugin :db` boot, every configured database is connected eagerly so
errors surface at startup.

`Lux.db(name)` returns the `Sequel::Database` for that name (default
`:main`). `DB` is a lazy proxy to `Lux.db(:main)`.

## Configuration

```yaml
# config/config.yaml
default:
  # simple form - one main database
  db: postgresql://localhost/myapp

  # or hash form - multiple named databases
  db:
    main: postgresql://localhost/myapp
    log:  postgresql://localhost/myapp_log

production:
  db:
    main: postgres://user:pass@host:5432/myapp
    log:  postgres://user:pass@host:5432/myapp_log
```

`DB_MAIN`, `DB_LOG`, ... environment variables override; otherwise falls
back to `Lux.config[:db_url]` for `:main`.

## Full example

```ruby
# --- access ---------------------------------------------------------
Lux.db                              # :main connection (Sequel::Database)
Lux.db(:log)                        # any named connection
DB[:users]                          # dataset on :main (via proxy)

# --- inspect --------------------------------------------------------
Lux::Db.connections                 # all active Sequel::Database instances
Lux::Db.configured_names            # [:main, :log] from config
Lux::Db.url_for(:main)              # resolved URL string

# --- management -----------------------------------------------------
Lux::Db.disconnect_all              # tear down all pools

# --- CLI tasks (see plugins/db hammer) -----------------------------
# lux db:info        # show configured databases and existence
# lux db:create      # create databases if missing
# lux db:drop        # drop all (blocked in production)
# lux db:reset       # drop, create, auto migrate
# lux db:am [y]      # auto-migrate schema (y to auto-confirm drops); in dev also rebuilds <db>_test
# lux db:seed        # reset + load seeds from ./db/seeds/
# lux db:backup      # SQL dump to ./tmp/db_dump/
# lux db:restore     # restore from SQL dump
# lux db:console     # psql console
# lux db:psql        # psql console alias
# lux db:check       # database size/table/version info
# lux db:exec --sql  # execute SQL against configured databases
# lux db:test:am     # force-rebuild test DBs (<db>_test) from the model schema
# lux db:test:drop   # drop test databases only
```

## See also

* [`../../../plugins/db/README.md`](../../../plugins/db/README.md) - Sequel model extensions, `link` associations, auto-migrate
* [`../schema/README.md`](../schema/README.md) - the schema DSL used by `model.schema do`
