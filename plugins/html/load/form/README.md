### HtmlForm

Form builder that wraps HtmlInput with form tags, labeled rows, and submit buttons.

#### Usage

```ruby
form = HtmlForm.new(user)
form.render do |f|
  f.row :name
  f.row :email
  f.row :bio, as: :textarea
  f.row :role, collection: Role.all
  f.hidden :account_id
  f.submit 'Save'
end
```

#### Standalone (no model)

```ruby
form = HtmlForm.new('/search', method: 'get')
form.render do |f|
  f.row :q, as: :string, value: params[:q]
  f.submit 'Search'
end
```

#### Methods

| Method     | Description                                    |
|------------|------------------------------------------------|
| `row`      | Labeled input row (delegates to HtmlInput)     |
| `input`    | Raw input without row wrapper                  |
| `hidden`   | Hidden input field                             |
| `submit`   | Submit button with optional cancel/back links  |
| `button`   | Custom button tied to a field value            |
| `fieldset` | Groups rows with optional title and description|
| `push`     | Push raw HTML into the form                    |
| `done`     | Set data-done callback                         |

#### Row options

All HtmlInput options plus:

| Option   | Description                          |
|----------|--------------------------------------|
| `:label` | Custom label text                    |
| `:hint`  | Small hint text below input          |
| `:info`  | Info text above input                |

#### Extending

Override `setup_object` in a subclass to customize object-based form initialization:

```ruby
class AppForm < HtmlForm
  private

  def setup_object
    super
    @opts[:action] = @object.api_path(@object.id ? :update : :create)
  end
end
```
