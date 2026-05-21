# Lux::Policy - agent guide

Access policies. **Define once, use on models / controllers / APIs.** Do
not write per-controller authorization branches - hoist to a policy.

## Canonical example

```ruby
class BlogPolicy < Lux::Policy
  def before action
    return true if user.can.admin?     # short-circuit for admins
  end

  def read?
    model.public? || model.created_by == user.id
  end

  def write?
    error 'Read-only on Sundays' if Time.now.sunday?
    model.created_by == user.id
  end
end

# Model auto-resolves <Model>Policy when including the mixin
class Blog < ApplicationModel
  include Lux::Policy::Model
end

@blog.can.read?          # bool
@blog.can.write!         # raises Lux::Policy::Error or returns @blog

# Controller mixin (auto-mixed into Lux::Controller)
authorize @blog.can.write?     # 403 if false
is_authorized!                 # raises if not authorized

# Headless policy
class DashboardPolicy < Lux::Policy
  def access?; user.role == :admin; end
end
DashboardPolicy.can.access?
```

## Rules

* **Class name = `<Model>Policy`** for auto-resolution via
  `Lux::Policy::Model`. Place in `app/policies/`.
* **Action methods end with `?`.** Inside, `model`, `user`, `action` are
  available. Return truthy to allow.
* **`before(action)` hook** on a policy class: truthy short-circuits to
  allow. Use for admin overrides.
* **`error 'msg'` inside an action** raises `Lux::Policy::Error` with the
  message; reported through the bang/block forms.
* **Current user** resolves from `Thread.current[:current_user]`, then
  `User.current`, then `Current.user`. Override
  `Lux::Policy.current_user` if your app uses a different identity source.
* **`.can`** returns a proxy; **`.can(user)`** overrides the user.
* **`.read?` vs `.read!`:** bool vs raise. Block forms swallow.

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
