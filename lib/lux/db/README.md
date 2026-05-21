# Lux::Db

Sequel multi-DB connection management. Connections are lazy; on
`Lux.plugin :db` boot, every configured database is connected eagerly so
errors surface at startup.

## Small example

```ruby
Lux.db                   # Sequel::Database for :main
Lux.db(:log)             # Sequel::Database for :log
DB                       # lazy proxy to Lux.db(:main)
```

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

`DB_MAIN`, `DB_LOG`, ... environment variables override, then falls back
to `Lux.config[:db_url]` for `:main`.

## Full example

```ruby
# Access
Lux.db                              # :main connection
Lux.db(:log)                        # any named connection
DB[:users]                          # dataset on :main (via proxy)

# Inspect
Lux::Db.connections                  # all active Sequel::Database instances
Lux::Db.configured_names             # [:main, :log] from config
Lux::Db.url_for(:main)              # resolved URL string

# Management
Lux::Db.disconnect_all              # tear down all pools

# Rake tasks (see ./tasks/db.rake) ----------------------------------
# rake db:info        # show configured databases and existence
# rake db:create      # create databases if missing
# rake db:drop        # drop all (blocked in production)
# rake db:reset       # drop, create, auto migrate
# rake db:am          # auto-migrate schema (db:am[y] to auto-confirm drops)
# rake db:seed        # reset + load seeds from ./db/seeds/
# rake db:backup      # SQL dump to ./tmp/db_dump/
# rake db:restore     # restore from SQL dump
# rake db:console     # psql console
# rake db:create:test # recreate test DBs (drop, copy schema from main)
# rake db:drop:test   # drop test databases only
```

## See also

* [`../../../plugins/db/README.md`](../../../plugins/db/README.md) - Sequel model extensions, `link` associations, auto-migrate
* [`../schema/README.md`](../schema/README.md) - the schema DSL used by `model.schema do`
* [`AGENTS.md`](./AGENTS.md) - LLM guide
