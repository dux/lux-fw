# Lux::Controller - agent guide

HTTP controllers. **Use `opt` and `params do` for any params contract -
identical DSL across `Lux::Controller`, `Lux::Api`, and `Lux::Schema`.**

## Canonical example

```ruby
class BoardsController < ApplicationController
  layout :application
  before { @user = User.current or Lux.error.unauthorized }

  # class-level params: apply to every action
  params do
    org_id type: :uuid
  end

  # method-level: union with class-level, method-wins on collision
  opt :name,   String, max: 30
  opt :tags?,  [String]
  def create
    board = @user.boards.create!(current.params.to_h)
    redirect_to "/boards/#{board.ref}"
  end

  def index
    @boards = @user.boards
  end

  # member actions (URL has an id segment) live inside `ref do`
  ref do
    def show
      @board = Board.find(nav.ref)
    end
  end
end
```

## Rules

* **Declared opts = strict.** If any `opt` line precedes a `def` (or any
  class-level `params do` is set), undeclared keys are dropped from
  `current.params`, required keys are validated, types are coerced.
* **No opts = loose.** Params pass through unchanged (existing behavior).
* **Method-wins on collision** with class-level `params do`.
* **Line forms accepted by `opt`:**
  * `opt :name, String, max: 30` ≡ `opt :name, type: String, max: 30`
  * `opt :name?, ...` marks the field optional
  * Same parser as `Lux::Schema::Define` (see
    [`../schema/AGENTS.md`](../schema/AGENTS.md))
* **422 vs HTML on validation error:** JSON requests halt 422 with
  `{ errors: { field: msg } }`; HTML requests stash errors in
  `current.var[:param_errors]` and the action runs so the page can
  re-render the form.
* **Validation timing:** between `before_action` callbacks and the action
  method. Before-filters see raw params; the action sees coerced.

## Actions that aren't `def`-defined

* `mock :show, :edit` generates empty methods (template-only actions).
* `action_missing(name)` falls back to a template lookup if
  `Lux.config.use_autoroutes` is set. Override per-controller for custom
  routing-by-method-name.

## Ref-bearing routes

URLs with id segments map to `:NAME_ref` actions. Group them in `ref do
... end` to keep `:show` (collection) and `:show_ref` (member) separate.
Template lookup probes `show_ref.haml` first, falls back to `show.haml`.

## Don't

* Hand-roll param validation - use `opt` / `params do`.
* Forget that `current.params` is the post-validation, coerced hash.
* Define a `def error` that doesn't read `@error` / `@status` - the
  framework sets them before dispatching the error action.
* Use `is_a?(Hash)` inside controller code - inside `module Lux`, `Hash`
  resolves to `Lux::Hash`. Use `obj.is_hash?`.

## See also

* [`Lux::Schema` AGENTS](../schema/AGENTS.md) - the DSL parser
* [`Lux::Api` AGENTS](../api/AGENTS.md) - same DSL for JSON APIs
* [`Lux::Application` AGENTS](../application/AGENTS.md) - routing into controllers
* [`Lux::Policy` AGENTS](../policy/AGENTS.md) - access control inside actions
