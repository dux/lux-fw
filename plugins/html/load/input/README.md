### HtmlInput

Form input helper that renders HTML form elements from model objects or standalone options.

#### Usage

```ruby
input = HtmlInput.new(user)
input.render :email                          # auto-detects type from schema
input.render :name, as: :string              # explicit type
input.render :bio, as: :textarea             # textarea
input.render :role, collection: Role.all     # select dropdown
input.render :active, as: :checkbox          # checkbox
input.hidden :user_id                        # hidden field
```

#### Standalone (no model)

```ruby
input = HtmlInput.new
input.render :query, as: :string, value: params[:query]
```

#### Accessing options

```ruby
input = HtmlInput.new(user, class: 'form-input')

# @opt - original constructor opts, frozen, never mutated
input.opt[:class]    # => 'form-input'

# @opts - working hash, mutated during render
input[:value]        # shortcut for input.opts[:value]
input[:class] = 'x'  # shortcut for input.opts[:class] = 'x'
```

#### Available types

| Type         | Description                          |
|--------------|--------------------------------------|
| `:string`    | Text input (default)                 |
| `:text`      | Alias for `:string`                  |
| `:password`  | Password input                       |
| `:email`     | Email input                          |
| `:hidden`    | Hidden input                         |
| `:date`      | Date picker                          |
| `:datetime`  | Datetime-local picker                |
| `:file`      | File upload                          |
| `:textarea`  | Multi-line text                      |
| `:memo`      | Textarea with wrap                   |
| `:checkbox`  | Checkbox (single or array)           |
| `:checkboxes`| Multiple checkboxes from collection  |
| `:select`    | Select dropdown from collection      |
| `:radio`     | Single radio button                  |
| `:radios`    | Radio group from collection          |
| `:tag`       | Tag input with visual preview        |
| `:color`     | Color picker with hex input          |
| `:geo`       | Geo coordinates with map link        |
| `:address`   | Address textarea with map link       |
| `:disabled`  | Disabled text input                  |

#### Auto-detection

When a model object is provided, the input type is auto-detected from:
1. Database column type (`timestamp` -> `:datetime`, `boolean` -> `:checkbox`, etc.)
2. Lux::Schema rules and metadata
3. Presence of `_id`/`_sid` suffix (auto-resolves collection)
4. Fallback to `:string`
