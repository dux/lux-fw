# Lux::Test - test authoring rules

This is the single source of truth for how lux specs are written. AI agents
writing or converting tests for lux **must** follow these rules. The point
is zero hallucinated matchers and zero invented helpers.

## Framework

* **Minitest::Spec** - `describe ... do; it '...' do; ...; end; end`
* Every `describe` block transparently mixes in `Lux::Test::Case` helpers,
  so all helpers below are instance methods inside every `it` block.
  Do not write `class FooTest < ...`.
* Run: `rake test` (or `ruby -Ilib -Ispec spec/path/to/foo_spec.rb`).

## Assertions - the entire allowed list

Use only these.

```ruby
# core minitest (always available)
assert  cond, msg=nil
refute  cond, msg=nil
assert_equal     expected, actual
refute_equal     expected, actual
assert_nil       actual
refute_nil       actual
assert_includes  collection, item
refute_includes  collection, item
assert_match     regex, str
assert_raises(ErrorClass) { ... }
assert_kind_of   klass, obj
assert_respond_to obj, :method
assert_empty     collection
refute_empty     collection
assert_in_delta  expected, actual, delta

# Lux::Test::Assertions (request-level)
assert_status         200, resp
assert_redirect       '/login', resp
assert_body_includes  'Hello', resp
assert_json_includes  { ok: true }, resp
```

Spec-style is also fine and preferred when the subject is obvious:

```ruby
_(value).must_equal     'foo'
_(value).must_be_nil
_(arr).must_include     :x
_(str).must_match       /foo/
_{ raise X }.must_raise X
```

## Banned

Do **not** use any of these. They are RSpec, not Minitest:

* `expect(x).to ...`, `expect { }.to raise_error`, `expect { }.to change { }`
* `eq`, `be_a`, `be_truthy`, `be_nil`, `match_array`, `contain_exactly`,
  `have_attributes`, `include` (as RSpec matcher), `change`, `raise_error`
* `let(:foo) { ... }`, `subject`, `described_class`
* `before(:all)`, `before(:each)` - use `before { ... }` only
* `context` - use a nested `describe` instead
* `shared_examples`, `it_behaves_like`, shared contexts
* `double`, `instance_double`, `allow(...).to receive(...)`, `expect(...).to receive(...)`
  - if you need a stub, use `Minitest::Mock` or a plain class with the methods you need

If a test seems to require any of the above, build it with the allowed
primitives or extend `Lux::Test::Assertions`. Do not invent matchers.

## Memoization (replacing `let`)

```ruby
# instead of: let(:user) { factory.create(:user) }
def user
  @user ||= factory.create(:user)
end
```

Minitest re-instantiates the test class per `it`, so `@user` is naturally
scoped to one example.

## Factories - `factory`

The only factory API. Defined in `lib/lux/test/factory/factory.rb`
(see its README for the full DSL).

```ruby
factory.build(:user)                 # User instance, not saved
factory.build(:user, :admin)         # with trait
factory.build(:user, email: 'x@y')   # with attribute override
factory.create(:user)                # build + save (if model responds to :save)
factory.fetch(:org)                  # memoized create on identical args
factory.attributes_for(:user)        # .attributes hash, present values only
```

**Where blueprints live**: `spec/factories.rb`. Add new ones there. Do not define
factories inside a spec file unless they are one-off and clearly local.

**State reset**: `Lux::Test::Factory.reset` is called in `before` by the
base class, so sequences and fetch cache start clean per test.

## HTTP requests

Use `Lux.render.<verb>` directly. It returns a `Lux::Response`.

```ruby
resp = Lux.render.get('/users', params: { q: 'x' }, session: { user_id: 1 })
resp = Lux.render.post('/users', params: { name: 'Dux' })

resp.status        # Integer
resp.body          # String
resp.json          # parsed JSON, symbol keys
resp.headers       # Hash
resp.redirect_to   # Location header value, or nil
resp.ok?           # true if 2xx
```

Verbs: `get`, `post`, `put`, `patch`, `delete`. Options: `params`, `session`,
`cookies`, `query_string`. Pass body data via `params:` for POST.

## Capture

```ruby
out = capture_stdout { Foo.print_thing }
err = capture_stderr { Foo.warn_thing  }
log = capture_log    { Foo.log_thing   }   # captures Lux.logger output
```

## DB

For specs that hit Postgres. The spec is responsible for setting the top-level
`DB` constant to a Sequel connection (see `spec/lux_tests/db_plugin_spec.rb`
for the canonical pattern).

```ruby
with_transaction do
  user = factory.create(:user)
  # ... assertions ...
end  # rolled back here

truncate :users, :orgs   # use when transaction wrapping won't work
```

## Pattern catalogue

### Controller / route test

```ruby
require 'test_helper'

describe Lux::Controller do
  it 'renders 200 for the index action' do
    resp = Lux.render.get('/users', session: { user_id: factory.create(:user).id })
    assert_status 200, resp
    assert_body_includes 'Users', resp
  end

  it 'redirects unauthed users to login' do
    resp = Lux.render.get('/dashboard')
    assert_redirect '/login', resp
  end
end
```

### Model / schema test

```ruby
require 'test_helper'

describe User do
  it 'is invalid without an email' do
    u = factory.build(:user, email: nil)
    refute u.valid?
    assert_includes u.errors[:email], 'cannot be blank'
  end

  it 'is admin via trait' do
    _(factory.build(:user, :admin).is_admin).must_equal true
  end
end
```

### Pure-lib unit test

```ruby
require 'test_helper'

describe Lux::Hash do
  describe '#slice' do
    it 'returns only requested keys' do
      h = { a: 1, b: 2, c: 3 }
      _(h.slice(:a, :b)).must_equal({ a: 1, b: 2 })
    end
  end
end
```

### Capturing IO

```ruby
require 'test_helper'

describe 'CLI output' do
  it 'prints the banner' do
    out = capture_stdout { Lux::Shell.banner }
    assert_includes out, 'Lux'
  end
end
```

## Rules summary (when in doubt)

1. Only assertions from the list above. No invented matchers.
2. No RSpec syntax anywhere. No `let`, no `expect`, no `double`.
3. Factories live in `spec/factories.rb`. One blueprint per concept.
4. Use `Lux.render.get/post/...` for HTTP-level tests. No raw `Lux.app.new`.
5. `capture_*` for IO, `with_transaction` for DB. Stub `Time.now` by hand
   when needed - there is no `freeze_time` helper.
6. Memoize via `def foo; @foo ||= ...; end`. Not `let`.
7. Each `it` is independent. State resets in `before` hooks of `Lux::Test::Case`.
