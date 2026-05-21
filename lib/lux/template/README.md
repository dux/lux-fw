# Lux::Template

Template rendering via [Tilt](https://github.com/rtomayko/tilt). Supports
HAML, ERB, and any other format Tilt knows. Helper modules are mixed
into the rendering scope.

## Small example

```ruby
Lux::Template.render(self, './app/views/users/show.haml')
```

## Full example

```ruby
# --- simple render -----------------------------------------------------

Lux::Template.render(self, './path/to/template.haml')

# --- render with explicit layout ---------------------------------------

Lux::Template.render(self, template: './template.haml', layout: './layout.haml')

# --- yield content into layout -----------------------------------------

Lux::Template.render(self, './layout.haml') { 'content to yield' }

# --- helper module mix (template gets the helper methods + ivars) ------

# define your helper module
module MainHelper
  def link_to(text, url)
    %[<a href="#{url}">#{text}</a>]
  end
end

# build a helper with scope + module list
helper = Lux::Template.helper(
  { '@user' => User.first },         # ivars
  :html, :main                       # mixes in HtmlHelper + MainHelper
)
helper.link_to 'Home', '/'

# inside a Lux::Controller, `helper` returns the same kind of object
class MainController < Lux::Controller
  def show
    helper.link_to 'Home', '/'       # MainHelper.link_to
    helper(:bar).format_date(...)    # BarHelper.format_date
  end
end

# --- inline render proxy (rare) ----------------------------------------

# Used by Lux::Mailer and a few internals to render templates without
# touching the response body. Usually you don't call this directly.
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
* [`AGENTS.md`](./AGENTS.md) - LLM guide
