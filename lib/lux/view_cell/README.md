# Lux::ViewCell

Reusable view components. Each cell is a class with its own templates,
helpers, and instance variables. Cells compose - a cell can render
another cell.

Subclass per component; instantiate directly or via `Lux.render.cell(:name)`.

## Full example

```ruby
# app/cells/user_cell.rb
class UserCell < ApplicationCell
  delegate :request, :params      # forward these calls to the parent scope

  # initializer is (parent, vars); keys in vars become @ivars on the cell
  def initialize parent = nil, vars = {}
    super
    @org = vars[:org]
  end

  def card
    template :card                # app/cells/user/card.haml
  end

  def avatar user, size: 64
    @user = user
    @size = size
    template :avatar              # app/cells/user/avatar.haml
  end

  def link
    %[<a href="/users/#{@user.ref}">#{@user.name}</a>]
  end
end

# --- ways to use -----------------------------------------------------

# direct
UserCell.new.card

# with parent scope (lets the cell reach parent ivars/helpers via `parent`)
UserCell.new(self).card

# with extra vars (become @ivars in the cell)
UserCell.new(self, org: @org).card

# via Lux.render.cell
Lux.render.cell(:user).card
Lux.render.cell(:user, self).card
Lux.render.cell(:user, self, org: @org).card

# from inside a template (HAML) - `cell` and `parent` are available there too
= cell(:user).card
= cell(:user, org: @org).avatar(@user, size: 128)
```

Each cell instance exposes three building blocks:

* `template name` - render a template by name from the cell's directory
* `cell ...`       - render another cell from inside this one
* `parent`         - the scope the cell was created with (`parent { @user }`
  reads an ivar from it); `delegate :foo` forwards `foo` to it

## Layout

```
app/cells/<name>/<method>.haml      # one template per cell method
app/cells/<name>/_partial.haml      # private partial (underscore-prefixed)
```

## See also

* [`../render/README.md`](../render/README.md) - `Lux.render.cell`
* [`../template/README.md`](../template/README.md) - templating internals
