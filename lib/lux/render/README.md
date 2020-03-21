## Lux.render

Render full pages and templates.

### Render full pages

As a first argument to any render method you can provide
full [Rack environment](https://www.rubydoc.info/gems/rack/Rack/Request/Env).

If you provide only local path,
[`Rack::MockRequest`](https://www.rubydoc.info/gems/rack/Rack/MockRequest) will be created.

Two ways of creating render pages are provided.

* full builder `Lux.render(@path, @full_opts)`
* helper builder with request method as method name `Lux.render.post(@path, @params_hash, @rest_of_opts)`

```ruby
# render options - all optional
opts = {
  query_string: {}
  post: {},
  body: String
  request_method: String
  session: {}
  cookies: {}
}

# when passing data directly, renders full page with all options
page = Lux.render('/about', opts)

# you can use request method prefix
page = Lux.render.post('/api/v1/orgs/list', { page_size: 100 }, rest_of_opts)
page = Lux.render.get('/search', { q: 'london' }, { session: {user_id: 1} })

page.info # gets info hash + body
# {
#   body:    '{}',
#   time:    '5ms',
#   status:  200,
#   session: { user_id: 123 }
#   headers: { ... }
# }

page.render # get only body
```


### Render templates

Renders templates, wrapper arround [ruby tilt gem](https://github.com/rtomayko/tilt).

```ruby
Lux.render.template(@scope, @template)
Lux.render.template(@scope, template: @template, layout: @layout_file)
Lux.render.template(@scope, @layout_template) { @yield_data }
```

Scope is any object in which context tmplate will be rendered.

* you can pass `self` so template has access to the same instance
  variables and methods as current scope.
* you can construct full valid helper with `Lux.template.helper(@scope, :foo, :bar)`.
  New helper class will be created from `FooHelper module and BarHelper module`,
  and it will be populated with `@scope` instance variables.

```ruby
  # HtmlHelper module or CustomModule has to define link_to method
  helper = Lux.template.helper(@instance_variables_hash, :html, :custom, ...)
  helper.link_to('foo', '#bar') # <a href="#bar">foo</a>
```

Tip: If you want to access helper mehods while in controller, just use `helper`.


### Render controllers

Render controller action without routes, pass a block to yield before action call
if you need to set up params or instance variables.

```ruby
Lux.render.controller('main/cities#foo').body
Lux.render.controller('main/cities#bar') { @city = City.last_updated }.body
```

