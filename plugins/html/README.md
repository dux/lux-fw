# Lux.plugin :html

HTML builders: form, input, table, menu, paginate, filter, plus
`PageMeta` and timezone helpers.

## Setup

```ruby
Lux.plugin :html
```

All builders become available immediately - they are pure Ruby and do not
need a database.

## Layout

```
plugins/html/
  load/
    html_filter.rb
    html_menu.rb
    html_paginate.rb
    page_meta.rb
    time_zones.rb
    form/
      html_form.rb
      html_form_custom.rb
    input/
      html_input.rb
      html_input_custom.rb
    table/
      html_table.rb
      html_table_app.rb
      html_table_custom.rb
```

Each subfolder has its own `README.md` and `spec/` directory.
