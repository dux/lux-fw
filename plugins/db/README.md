# Lux.plugin :db

Database integration for Lux. Boots `Lux::Db` and registers Sequel model
extensions (hooks, links, parent_model, enums, paginate, ...).

## Setup

```ruby
Lux.plugin :db
```

`loader.rb` calls `Lux::Db.boot!` and configures
`Sequel::Model.require_valid_table = false` under rake tasks. All Sequel
plugins and helpers in `load/` are then auto-required.

## CLI

```
lux db:am                   # auto-migrate model schemas
lux db:backup               # back up configured databases
lux db:restore              # restore from backup
```

(See `hammer/db_hammer.rb` for the full task list.)

## Layout

```
plugins/db/
  loader.rb                  # Lux::Db.boot!
  load/                      # Sequel plugins + auto_migrate runtime
    core.rb
    hooks.rb
    link_objects.rb
    ...
    auto_migrate.rb
    wip/                     # experimental, still auto-loaded
  hammer/
    db_hammer.rb             # `lux db:*` CLI tasks
```
