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

## Ref linking

`Sequel::Plugins::RefLinker` (see `plugins/_ref_linker.rb`) is the single
owner of `*_ref` column conventions. It recognises four field shapes:

| Shape       | Columns                       | Direction                    |
|-------------|-------------------------------|------------------------------|
| `:scalar`   | `<name>_ref`                  | belongs_to one record        |
| `:array`    | `<name>_refs` (text[])        | has_many via array of refs   |
| `:poly_key` | `parent_key` ("Class/ref")    | polymorphic belongs_to (1col)|
| `:poly_pair`| `parent_type` + `parent_ref`  | polymorphic belongs_to (2col)|

Public surface:

```ruby
class Task < ApplicationModel
  plugin :ref_linker        # or :lux_links / :parent_model (aliases)
  link :user                # belongs_to via user_ref
  link :comments            # has_many via Comment.task_ref OR parent_key
end

Task.where_ref(@user)       # class-level scope
Task.dataset.for(@user)     # dataset-level scope (alias: where_ref)
note.parent = @user         # writes parent_key OR parent_type+parent_ref
note.parent                 # reads back the parent
```

The old `for_parent` / `where_parent` / `where_for` methods were removed
in favour of `for` / `where_ref`.

## Layout

```
plugins/db/
  loader.rb                  # explicit require list (no Dir sweep)
  lib/                       # pure-Ruby utilities (no Sequel)
    ref.rb                   # Lux::Utils::Ref (16-char ID generator)
    ref_type.rb              # Lux::Type::RefType
    schema_define.rb         # Lux::Schema::Define#timestamps DSL helper
  ext/                       # direct Sequel::Model extensions
    core.rb
    dataset_methods.rb       # x* query-builder primitives
    dataset_scopes.rb        # convenience scopes layered on dataset_methods
    find_precache.rb
    paginate.rb
    logger.rb
    model_tree.rb
    enums_plugin.rb
  plugins/                   # Sequel plugins (registered via `plugin :name`)
    _ref_linker.rb           # Sequel::Plugins::RefLinker (+ :LuxLinks / :ParentModel aliases)
    hooks.rb
    before_save_filters.rb
    create_limit.rb
    composite_primary_keys.rb
  migrate/                   # schema migration runtime (used by `lux db:am`)
    auto_create_tables.rb
    auto_migrate.rb
  wip/                       # experimental
  hammer/
    db_hammer.rb             # `lux db:*` CLI tasks
```
