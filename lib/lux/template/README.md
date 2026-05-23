# Lux::Template

Template rendering via [Tilt](https://github.com/rtomayko/tilt). Supports
HAML, ERB, and any other format Tilt knows. Helper modules are mixed
into the rendering scope.

`Lux.template` returns the `Lux::Template` module.

## Full example

```ruby
# --- render a template directly -----------------------------------------

Lux.template.render(self, './app/views/users/show.haml')

# --- explicit layout ----------------------------------------------------

Lux.template.render(self, template: './template.haml', layout: './layout.haml')

# --- yield content into a layout ---------------------------------------

Lux.template.render(self, './layout.haml') { 'content to yield' }

# --- build a helper (used by Lux::Mailer / out-of-controller rendering) -

# define your helper module
module MainHelper
  def link_to(text, url)
    %[<a href="#{url}">#{text}</a>]
  end
end

helper = Lux.template.helper(
  { '@user' => User.first },     # ivars exposed in the helper scope
  :html, :main                   # mixes HtmlHelper + MainHelper
)
helper.link_to 'Home', '/'

# Inside a Lux::Controller, `helper` returns the same kind of object:
class MainController < Lux::Controller
  def show
    helper.link_to 'Home', '/'   # MainHelper#link_to (matches controller name)
    helper(:bar).format_date(t)  # BarHelper#format_date
  end
end
```

## Conventions

* Templates live under `./app/views/<controller>/<action>.haml` (Lux
  default; override with `template_root` on the controller).
* `app/views/layouts/<name>.haml` for layouts; `<controller>Helper`
  module for per-controller helpers.
* Production: Tilt caches compiled templates. Dev: recompiled on every
  request.

## See also

* [`../render/README.md`](../render/README.md) - `Lux.render.template`
* [`../controller/README.md`](../controller/README.md) - `render`, `helper`
* [`../view_cell/README.md`](../view_cell/README.md) - reusable components
