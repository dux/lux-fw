# DB Plugin - Sequel ORM extensions

All models use ULID `:ref` as primary key (no `:id` column).

## File layout

| File | Purpose |
|------|---------|
| `loader.rb` | Boot file, loads all others |
| `core.rb` | ClassMethods: `scope`, `iscope`, `find_by`, `first_or_new`, `first_or_create`. InstanceMethods: `key`, `cache_key`, `attributes`, `creator`, `updater`, `has?`, `unique?`, `save!`, `slice`, `init`, `merge`, `on_change` |
| `dataset_methods.rb` | ALL dataset/query methods (see below) |
| `before_save_filters.rb` | Lifecycle: timestamps, creator/updater audit, cache invalidation on save/destroy, soft-delete via `is_deleted` column |
| `hooks.rb` | `before`/`after` DSL for `:create`, `:update`, `:destroy` (shorthand `:cu`, `:cud`) |
| `link_objects.rb` | `link`/`ref` DSL for associations. ClassMethods: `where_ref` |
| `find_precache.rb` | `Model.find(ref)` with request-scoped + optional global cache. `Model.take(ref)` returns nil on miss |
| `paginate.rb` | `PaginatedArray`, `Paginate()` function, dataset `.page`/`.paginate` |
| `_parent_model.rb` | Polymorphic parent via `parent_key` (single "Class/ref" string) or `parent_model + parent_ref` (two columns) |
| `enums_plugin.rb` | String enum DSL (`_sid` fields). `enums :steps, values: {...}` |
| `create_limit.rb` | Rate limiting: `create_limit 30, 1.day` |
| `model_tree.rb` | Tree structure via `parent_refs` text[] column |
| `composite_primary_keys.rb` | Uniqueness check for composite keys |
| `auto_create_tables.rb` | Creates table with ref PK if missing during migration |
| `logger.rb` | SQL query logging with timing |

## Dataset methods (dataset_methods.rb)

All available on any model dataset:

* **Query helpers**: `xwhere`, `xlike`, `xselect`, `xorder`, `xfrom`, `random`
* **Scoping**: `for(obj)` / `where_for` / `where_ref` - auto-detect link column to parent object
* **Ordering**: `desc(:field)`, `asc`, `latest` (by updated_at)
* **Array columns**: `where_any(data, :field)`, `where_all(data, :field)`, `all_tags`
* **Boolean scopes**: `not_deleted`, `deleted`, `activated`, `deactivated` (safe no-op if column missing)
* **Pagination**: `page(size: 20)` / `paginate`
* **Utilities**: `pluck(:field)`, `ids(:field)`, `refs(limit)`, `last(n)`, `last_updated`

## Hooks DSL (hooks.rb)

```ruby
before :create do ... end
before :update do ... end
before :cu do ... end      # create + update
after :destroy do ... end
```

## Link DSL (link_objects.rb)

```ruby
link :user              # belongs_to via user_ref column
link :users             # has_many via user_refs[] or reverse lookup
link :user, class: 'OrgUser'   # custom class
link :user, field: 'owner_ref' # custom field
```

## Parent model (_parent_model.rb)

Two supported patterns:
* `parent_key` - single text column storing "ClassName/ref"
* `parent_model` + `parent_ref` - two columns

```ruby
@obj.parent = other_model
@obj.parent              # resolve parent
Model.for_parent(obj)    # query children
```

## Enums (enums_plugin.rb)

```ruby
enums :steps, values: { 'o' => 'Open', 'w' => 'Waiting' }
# creates: step_sid column, .step method, .steps class method
```
