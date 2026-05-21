# Lux::ViewCell

Reusable view components. Each cell is a class with its own templates,
helpers, and instance variables. Cells compose: a cell can render
another cell.

## Small example

```ruby
# app/cells/user_cell.rb
class UserCell < ApplicationCell
  def avatar user
    @user = user
    render :avatar           # renders app/cells/user/avatar.haml
  end
end

# in a template or controller:
UserCell.new.avatar(@user)
Lux.render.cell(:user).avatar(@user)
```

## Full example

```ruby
class UserCell < ApplicationCell
  helper :avatar             # mixes AvatarHelper into render scope

  # initializer args become instance vars in the cell
  def initialize ctx = nil, opts = {}
    super
    @org = opts[:org]
  end

  def card
    render :card             # app/cells/user/card.haml
  end

  def avatar user, size: 64
    @user = user
    @size = size
    render :avatar, layout: false
  end

  def link
    "<a href=\"/users/#{@user.ref}\">#{@user.name}</a>"
  end
end

# --- ways to use ------------------------------------------------------

# direct
UserCell.new.card

# with context (gives the cell access to controller ivars / helpers)
UserCell.new(self).card

# with extra opts
UserCell.new(self, org: @org).card

# via Lux.render.cell
Lux.render.cell(:user).card
Lux.render.cell(:user, self).card
Lux.render.cell(:user, self, org: @org).card

# from inside a template (HAML)
= cell(:user).card
= cell(:user, org: @org).avatar(@user, size: 128)
```

## Layout

```
app/cells/<name>/<method>.haml      # template per cell method
app/cells/<name>/_partial.haml      # private partial (underscore-prefixed)
```

## See also

* [`../render/README.md`](../render/README.md) - `Lux.render.cell`
* [`../template/README.md`](../template/README.md) - templating internals
* [`AGENTS.md`](./AGENTS.md) - LLM guide
