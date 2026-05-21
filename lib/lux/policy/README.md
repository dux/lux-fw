# Lux::Policy

Framework- and ORM-agnostic access policy. Inherit, define question-mark
methods, use everywhere - on models, in controllers, in APIs. Same shape
in all three.

## Small example

```ruby
class BlogPolicy < Lux::Policy
  def read?
    model.created_by == user.id
  end

  def write?
    user.admin? || read?
  end
end

@blog.can.read?   # true / false
@blog.can.write!  # returns model on success, raises Lux::Policy::Error on fail
```

## Full example

```ruby
# 1. Define ---------------------------------------------------------------

class BlogPolicy < Lux::Policy
  # before-hook: truthy short-circuits to allow
  def before action
    return true if user.can.admin?
  end

  def read?
    model.public? || model.created_by == user.id
  end

  def write?
    error 'Read-only on Sundays' if Time.now.sunday?
    model.created_by == user.id
  end

  def comment?
    user.subscribed?
  end
end

# 2. Use on a model (auto-resolves <Model>Policy) -------------------------

class Blog < ApplicationModel
  include Lux::Policy::Model
end

@blog.can.read?                  # uses Lux::Policy.current_user
@blog.can(@another_user).read?   # explicit user
@blog.can.write!                 # returns @blog, raises on fail
@blog.can.write! { |msg| flash.error msg }   # block runs on fail, no raise

# 3. Use in a controller -------------------------------------------------

class BlogsController < ApplicationController
  before { @blog = Blog.find(nav.ref) }

  def show
    @blog.can.read!     # raises 403 if denied
    render :show
  end

  def update
    authorize @blog.can.write?    # marks request authorized or raises
    @blog.update(current.params.to_h)
  end
end

# 4. Headless policy (no model) -----------------------------------------

class DashboardPolicy < Lux::Policy
  def access?
    user.role == :admin
  end
end

DashboardPolicy.can.access?
authorize DashboardPolicy.can.access?

# 5. Explicit invocation ------------------------------------------------

Lux::Policy.can(model: @blog, user: @user).read?
BlogPolicy.can(model: @blog, user: @user).write!
```

## Current-user resolution

`Lux::Policy.current_user` resolves in order:

1. `Thread.current[:current_user]`
2. `User.current` (if `User` is defined and responds to `current`)
3. `Current.user` (if `Current` defined)
4. Raises `RuntimeError` if none of the above

Override `Lux::Policy.singleton_method(:current_user)` to plug your own
resolver.

## Proxy actions

`model.can` returns a `Lux::Policy::Proxy`:

| Method | Returns | On failure |
|--------|---------|------------|
| `proxy.read?`      | `true` / `false` | swallows `Lux::Policy::Error` |
| `proxy.read!`      | the `model`      | raises `Lux::Policy::Error` |
| `proxy.read?` w/ block | `true` / `false` | calls block with error message |
| `proxy.read!` w/ block | `true` / `false` | calls block, no raise |

## Controller mixin

`Lux::Policy::Controller` is auto-mixed into `Lux::Controller`:

```ruby
authorize @blog.can.read?       # truthy → authorized; falsy → 403
is_authorized?                  # boolean
is_authorized!                  # 403 if not authorized
```

## See also

* [`Lux::Error` README](../error/README.md) - HTTP 403 / `unauthorized!`
* [`AGENTS.md`](./AGENTS.md) - LLM guide
