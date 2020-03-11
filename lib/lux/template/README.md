## Lux.template (Lux::Template)

Renders templates, wrapper arround [ruby tilt gem](https://github.com/rtomayko/tilt).

```ruby
Lux.template.render(@scope, @template)
Lux.template.render(@scope, template: @template, layout: @layout_file)
Lux.template.render(@scope, @layout_template) { @yield_data }
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

