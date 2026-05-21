# Lux::Render - agent guide

Render pages, controllers, templates, view cells without an HTTP server.

## Canonical example

```ruby
# full-page render through the router
page = Lux.render.get('/search', query_string: { q: 'london' }, session: { user_id: 1 })
page.body
page.status
page.headers

# bypass the router, run a controller action directly
Lux.render.controller('users#show') { @user = User.first }.body

# template
Lux.render.template(self, './app/views/mailer/welcome.haml')

# view cell
Lux.render.cell(:user, self, product: @bar).in_a_box
```

## Rules

* **`Lux.render` is the entry point.** Returns an `Application::Render`
  module if called with no args (for chaining the verb shortcuts).
* **`get` / `post` / `put` / `patch` / `delete`** are shortcuts; they
  build a `Rack::MockRequest` env, instantiate the app, and run the
  request through the router.
* **`controller(name)`** skips routing and runs the action directly.
  Pass a block to set ivars / params before the action runs.
* **`template(scope, path_or_opts, &block)`** wraps `Tilt`. Scope is
  the object the template sees as `self`.
* **`cell(name, ctx, opts)`** instantiates a `Lux::ViewCell` and returns
  it for method-chaining (e.g. `.in_a_box(@user)`).
* **The page return value is a hash** with keys `body`, `status`,
  `headers`, `session`, `time`.

## Don't

* Don't call `Lux.app.new` directly - use `Lux.render`, which sets up
  the env properly and returns the parsed response hash.
* Don't pass instance variables through `params` - use the block form
  on `controller(...)`.
* Don't bypass `Lux.render.template` to call `Tilt` directly - the
  helper wiring (scope, layout, helper-modules) only happens via
  `Lux::Template.render`.

## CLI

`bin/cli/render_hammer.rb` exposes `lux render /path` with the same
options as the Ruby API.

## See also

* [`Lux::Template` AGENTS](../template/AGENTS.md)
* [`Lux::ViewCell` AGENTS](../view_cell/AGENTS.md)
* [`Lux::Controller` AGENTS](../controller/AGENTS.md)
