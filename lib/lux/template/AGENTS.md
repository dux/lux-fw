# Lux::Template - agent guide

Tilt-based rendering with helper module mixing.

## Canonical example

```ruby
# inside a controller, render a template by name (Lux::Controller#render does this)
Lux::Template.render(self, './app/views/users/show.haml')

# layout + content
Lux::Template.render(self, template: 'show.haml', layout: 'layouts/main.haml')

# yield content into layout
Lux::Template.render(self, 'layouts/main.haml') { '<h1>inner</h1>' }

# build a scope w/ ivars + helper modules
helper = Lux::Template.helper(
  { '@user' => current.user },
  :html, :main          # HtmlHelper + MainHelper
)
helper.link_to 'Home', '/'
```

## Rules

* **Scope = first arg.** Whatever you pass becomes the template's `self`.
  Pass the controller (`self` from a controller action) so the template
  can call its methods and read its ivars.
* **Helpers are modules,** named `<X>Helper`, mixed into the scope by
  `Lux::Template.helper(scope, :x, :y, ...)`. Controllers' `helper`
  method calls this with the controller's ivars.
* **Layout is just another template** with a `yield` in it. The framework
  passes the inner-rendered string into the block.
* **Tilt caches** compiled templates in production; recompiles per
  request in dev.
* **Don't roll your own Tilt scope** - go through `Lux::Template` so
  the helper-module mixing works.

## Don't

* Build HTML strings in controllers - use templates.
* Reach into Tilt directly - the helper-module wiring is here.
* Pass a hash as scope expecting method access; use `Lux::Template.helper`
  to convert ivars into a real object.

## See also

* [`Lux::Render` AGENTS](../render/AGENTS.md) - `Lux.render.template`
* [`Lux::ViewCell` AGENTS](../view_cell/AGENTS.md)
