# Controller merged into Router - what app authors need to change

`Lux::Controller` is gone and `Lux::Application` is now `Lux::Router`.
One class owns routing, actions and rendering, and `map` is the only routing word.
Canonical docs: [`../lib/lux/router/README.md`](../lib/lux/router/README.md).

## Files and classes

* `git mv app/controllers/<x>_controller.rb app/routers/<x>_router.rb`.
* `XController` becomes `XRouter`; `ApplicationController < Lux::Controller` becomes `ApplicationRouter < Lux::Router`.
* Plugin classes follow: `AuthcogController` is `AuthcogRouter`, `PdfController` is `PdfRouter`, `DevController` is `DevRouter`.
  `PdfRouter` and `DevRouter` subclass the app's `FrontendRouter`.
* `Lux::Policy::Controller` is `Lux::Policy::Authorize`.

## app/routes.rb

| Before | After |
|--------|-------|
| `Lux.app do` | `Lux.router do` |
| `routes do ... end` | `route do ... end` |
| top-level `map` / `root` in `Lux.app do` | inside `route do` |
| `call 'promo#auto'` | `map 'promo#auto'` |
| `call MainController` / `call 'main'` | `map MainRouter` |
| `call { 'text' }` | `render text: 'text'` |
| `body 'stop'` | `render text: 'stop'` |
| `root 'main'` | `root 'main'` (mounts `MainRouter`: runs its `route`, else resourceful `:index`) |

`rescue_from { call 'promo#app_error' }` becomes `rescue_from { map 'promo#app_error' }`.
The handler runs on the innermost router that was running, so its ivars (`@error`, `@status`, loaded models) pass along.

## Routers

* The controller `filter do |mount_on| ... end` tree becomes the router's `route do ... end` with nested `map` scopes, ending in `auto`:

  ```ruby
  route do
    map :spaces, :ref, :admin do
      @space.can.update!
    end
    auto
  end
  ```

* The empty-path resourceful action is `:index` (was `:root`); rename `def root` to `def index` and `views/<x>/root.haml` rendered by that action to `index.haml`.
  Templates found by `auto` keep their `root.*` names.
* `before_action` is gone; use `before` (runs once when the router is mounted) or a guard at the top of the action.
* `after` runs on the root router only (`Lux.router do after { } end`).
* `render` and `redirect_to` end the router; move statements that must still run before them.
* An action may not be named after the routing DSL (`map`, `root`, `auto`, `action`, `render`, `redirect_to`, `layout`, ...).
  `call`, `run`, `error` and `user` are fine.

## Removed

* `Lux.render.controller('x#y')` - use `XRouter.action(:y)` or `Lux.render.get`.
* `Lux::Error.render` - the router `error` action renders the error page.
* `Lux.ctx.var[:lux_app]` is `Lux.ctx.var[:lux_router]`; the dispatch log key is `router` (`MainRouter#index`).
