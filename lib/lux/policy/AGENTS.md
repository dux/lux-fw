# Lux::Policy - agent guide

Access policies. **Define once, use on models / controllers / APIs.** Do
not write per-controller authorization branches - hoist to a policy.

## Canonical example

```ruby
# app/models/application_policy.rb -- base class with shared helpers
class ApplicationPolicy < Lux::Policy
  private

  # raise + display "please sign in" if no user is logged in
  def session?
    return true if @user
    error 'Please sign in'
  end

  def is_admin?
    @user && @user.role == 'admin'
  end

  # creator-owned record check
  def my?
    session? && @user.ref == @model[:creator_ref]
  end

  def my_or_admin?
    is_admin? || my?
  end
end

# app/models/blog/blog_policy.rb
class BlogPolicy < ApplicationPolicy
  def before action
    return true if is_admin?       # admin override across every action
  end

  def read?
    @model.public? || my?
  end

  def write?
    error 'Read-only on Sundays' if Time.now.sunday?
    my?
  end
end

# usage
@blog.can.read?                    # bool
@blog.can.write!                   # raises Lux::Policy::Error or returns @blog
authorize @blog.can.write?         # in a controller: 403 on fail
is_authorized!                     # raises if not authorized

# Headless policy (no model)
class DashboardPolicy < ApplicationPolicy
  def access?
    is_admin?
  end
end
DashboardPolicy.can.access?
```

## Rules

* **Class name = `<Model>Policy`** for auto-resolution via
  `Lux::Policy::Model`. Place in `app/models/<model>/<model>_policy.rb`.
* **Define an `ApplicationPolicy < Lux::Policy`** as the app's base.
  Add shared private helpers there (`session?`, `is_admin?`, `my?`,
  `my_or_admin?`) and inherit per-model policies from it.
* **Action methods end with `?`.** Inside, prefer ivar access (`@user`,
  `@model`) over the `user` / `model` readers - matches the real-world
  style and reads consistently with the helper privates below.
* **`before(action)` hook** on a policy class: truthy short-circuits to
  allow. Use for admin overrides (`return true if is_admin?`).
* **`error 'msg'` inside an action** raises `Lux::Policy::Error` with
  the message. The message is **user-facing** - keep it short, in the
  app's language, suitable for a flash.
* **Current user** resolves from `Thread.current[:current_user]`, then
  `User.current`, then `Current.user`. Override
  `Lux::Policy.current_user` if your app uses a different identity source.
* **`.can`** returns a proxy; **`.can(user)`** overrides the user.
* **`.read?` vs `.read!`:** bool vs raise. Block forms swallow the
  raise and yield the message.

## Don't

* Put access checks inline in controllers. Hoist to a policy so APIs and
  models share the rule.
* Duplicate policies. One per model. `before` + question-mark methods is
  enough for nearly all cases.
* Couple to a specific ORM - `model.created_by` is up to your model; the
  policy doesn't care.

## See also

* [`Lux::Controller` AGENTS](../controller/AGENTS.md) - `authorize` helper
* [`Lux::Error` AGENTS](../error/AGENTS.md) - 403 / 401 helpers
