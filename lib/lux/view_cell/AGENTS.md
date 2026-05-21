# Lux::ViewCell - agent guide

Reusable view components. One class per cell; one template per method.

## Canonical example

```ruby
# app/cells/user_cell.rb
class UserCell < ViewCell
  helper :avatar           # AvatarHelper mixed into the render scope

  # before-filter: pull shared ivars from the parent context via `parent { }`
  before do
    @space = parent { @space }
    @user  = parent { @user }
  end

  def card
    render :card           # -> app/cells/user/card.haml
  end

  def avatar user, size: 64
    @user = user
    @size = size
    render :avatar, layout: false
  end
end

# use it
UserCell.new.card                     # standalone
UserCell.new(self).card               # with controller context
Lux.render.cell(:user, self).card     # via Lux.render
# in a HAML template:                  = cell(:user).avatar(@user, size: 128)
```

## Rules

* **Inherit from `ViewCell` directly.** There is no `ApplicationCell` -
  the framework's `Lux::ViewCell` exposes `ViewCell` at the top level.
* **One template per public method.** Naming: `app/cells/<name>/<method>.haml`.
  Partials use leading underscore.
* **Instance vars set inside the method** are visible in the template.
* **`helper :foo`** mixes `FooHelper` into the render scope (same
  mechanism as controllers).
* **Context** is passed as first init arg (`UserCell.new(self)`). Gives
  the cell access to the caller's ivars/helpers - useful for controller
  context.
* **`parent { @ivar }`** reads an ivar from the calling context. Common
  pattern inside a `before do ... end` block to hoist shared state
  (current user, current space) into the cell.
* **`Lux.render.cell(:name, ctx, opts)`** is the canonical entry point
  from outside; `cell(:name)` is the in-template shortcut.

## Don't

* Build cells that hit the DB on every render without caching - use
  `current.cache` for request-scope memoization.
* Pass huge state in cell opts - keep cells small and focused.
* Replace partials with cells reflexively - simple partials are fine;
  cells are for components with their own logic.

## See also

* [`Lux::Render` AGENTS](../render/AGENTS.md)
* [`Lux::Template` AGENTS](../template/AGENTS.md)
