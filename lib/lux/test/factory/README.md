# Lux::Test::Factory

Vendored from [clean-mock 0.2.3](https://github.com/dux/clean-mock), renamed
and namespaced under `Lux::Test::Factory`. It's a factory in the FactoryBot
sense - builds real instances of your real model classes from named
blueprints. No method-call mocking, no doubles, no `expect(...).to receive`.

The `factory` helper is exposed inside every `describe` block via
`Lux::Test::Case`; tests don't need to require anything.

## Quick reference

```ruby
# define
factory :user do |user, opts|
  user.name  = 'User %s' % sequence(:user)
  user.email = opts[:email] || 'u%s@test.com' % sequence

  trait :admin do
    user.is_admin = true
  end

  trait :with_org do
    create :org  # sets user.org_id = factory.create(:org).id
  end

  after_save do
    # runs after `create` / `fetch`, not on `build`
  end
end

# use
factory.build(:user)                    # User instance, not saved
factory.build(:user, :admin)
factory.build(:user, email: 'x@y')
factory.create(:user, :admin)           # build + save
factory.fetch(:org)                     # memoized create on identical args
factory.attributes_for(:user)           # filtered .attributes hash
```

## Differences from upstream clean-mock

* Renamed: top-level `CleanMock` -> `Lux::Test::Factory`.
* No `Object#mock` injection. `factory` is provided only inside
  Minitest::Spec via `Lux::Test::Case`.
* No ActiveSupport dependency. Lux already defines
  `String#classify/constantize/singularize` (see `lib/overload/string.rb`).
* `attributes_for` filter uses `!v.nil? && v != ''` (no ActiveSupport
  `present?`).
* `Factory.reset` clears sequences + fetch cache between tests (called
  from the `before` hook in `Lux::Test::Case`).

## Updating upstream clean-mock

If you fix a bug here, port it back to `~/dev/dux/gems/clean-mock` and bump
that gem. The lux copy is authoritative for lux's own specs; the gem
remains usable by other projects.
