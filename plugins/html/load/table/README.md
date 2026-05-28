### HtmlTable

Renders HTML tables from Sequel dataset scopes with sorting, search and column configuration.

#### Usage

```ruby
t = HtmlTable.new(scope, class: 'users-table')
t.col :name
t.col :email, sort: true
t.col :status, align: :c, width: 100
t.col(title: 'Actions') { |user| link_to('Edit', edit_path(user)) }
t.onclick { |user| "window.location='%s'" % user_path(user) }
t.render
```

#### Column options

| Option   | Description                                        |
|----------|----------------------------------------------------|
| `:field` | Symbol - model attribute to display                |
| `:title` | Custom header text (defaults to humanized field)   |
| `:sort`  | `true`, `:a` (default asc), `:d` (default desc), or Symbol to sort by different field |
| `:align` | `:l`, `:c`, `:r` (or `:left`, `:center`, `:right`)|
| `:width` | Column width in pixels                             |
| `:as`    | Type coercion via `as_*` methods (see below)       |
| `:block` | Block for custom cell rendering                    |

#### Column types (as:)

| Type        | Description                              |
|-------------|------------------------------------------|
| `:boolean`  | Checkmark for true, empty for false      |
| `:date`     | Format as `YYYY-MM-DD`                   |
| `:datetime` | Format as `YYYY-MM-DD HH:MM`            |
| `:number`   | Integer with comma separators            |
| `:currency` | Two decimal places                       |
| `:percent`  | Multiply by 100, append `%`             |
| `:truncate` | Truncate to `:limit` chars (default 50)  |
| `:email`    | Mailto link                              |
| `:link`     | Anchor tag, optional `:href` proc        |
| `:image`    | Img tag, uses `:width` (default 40px)    |
| `:list`     | Join array with `, `                     |

The types above belong to the base `HtmlTable`. The app-facing `table`
helper (`ApplicationHelper#table`) builds an `AppTable` instead, which
defines its own `as:` set tuned for application models:

| Type           | Description                                          |
|----------------|------------------------------------------------------|
| `:boolean`     | `Yes` (green) for true, `-` otherwise                |
| `:image`       | `<ui-asset>` tag (asset id or raw HTML/URL)          |
| `:url`         | Anchor linking to the field's own value              |
| `:email`       | Mailto link                                          |
| `:bold`        | Wrap value in `<b>`                                  |
| `:ago`         | Relative time (`Time.ago`), defaults to `created_at` |
| `:user`        | Record's `creator` name (optionally with email)      |
| `:scope_link`  | Linked button to the associated record's `scope_path`|
| `:object`      | Associated record rendered as a scope link           |
| `:sentence`    | Array joined to a sentence (models become links)     |
| `:tags`        | Array joined with `&sdot;`                            |
| `:date`        | Short date                                           |
| `:time`        | Long datetime                                        |
| `:html`        | Render value as HTML-safe                            |
| `:delete`      | Trash icon that calls the destroy API                |

`AppTable` also adds column helpers such as `id`, `avatar`, `count`,
`delete`, `callback`, `href`, `dialog`, and `idialog`.

#### Search

```ruby
t.search :q do |scope, value|
  scope.xlike(value, :name, :email)
end
```

#### Sorting

Sorting is driven by the `t-sort` query parameter with format `a-field` (ascending) or `d-field` (descending).

Initial sort can be set per column:
```ruby
t.col :name, sort: :a    # default ascending
t.col :score, sort: :d   # default descending
t.col :email, sort: true  # sortable, no default
```

URL params override the initial sort.

#### Scope helpers

```ruby
t.default_order { |scope| scope.order(:created_at) }
t.scope_filter { |scope| scope.where(active: true) }
```
