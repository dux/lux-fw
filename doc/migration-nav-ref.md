# Nav refs are objects now - what app authors need to change

`nav.map_path { }` used to replace an id segment with the `:ref` **symbol** and park
the value in a parallel `nav.refs` array. It now replaces the segment with an
object that carries its own value.

```ruby
# before
nav.path      # ['boards', :ref, 'edit']
nav.refs      # ['abc123']

# after
nav.path      # ['boards', #<RefString "abc123">, 'edit']
nav.refs      # ['abc123']       - derived from the path, not stored
```

`nav.ref`, `nav.refs` and router captures still hand back plain values, so most
app code is untouched. What changes is code that inspects `nav.path` itself.

Canonical docs: [`../lib/lux/application/README.md`](../lib/lux/application/README.md)
and [`../lib/lux/controller/README.md`](../lib/lux/controller/README.md).

## Why

The value lived in a second array indexed by counting `:ref` symbols to the left
of a segment. Two things broke that count:

* `nav.path[1] = board.ref` - documented and encouraged - removed a placeholder,
  so every capture to its right silently returned the *previous* ref.
* A second `nav.map_path { }` pass with a different classifier appended to `nav.refs`
  in its own discovery order, so the array stopped matching path order.

Both are impossible now: there is one array, and the value travels with the
segment.

## What you have to change

### `:ref` comparisons against `nav.path`

There is no placeholder symbol any more.

```ruby
# before
i = nav.path.index(:ref)
nav.path.each { |s| next if s == :ref }

# after
i = nav.path.index { _1.is_a?(Lux::Application::Nav::Base) }
nav.path.each { |s| next if s.is_a?(Lux::Application::Nav::Base) }
```

### `nav.pathname` and `nav.to_s` render real ids

A classified segment stringifies to its value, not to `ref`.

```ruby
# GET /boards/abc123/edit, after classification
nav.pathname          # '/boards/abc123/edit'   (was '/boards/ref/edit')
nav.normalized_path   # ['boards', 'ref', 'edit']
```

If you want the URL's *shape* rather than its values, that is what
`nav.normalized_path` is for - it puts every classified id back as the literal
`'ref'`. There are now three views of the path:

| reader | what it is |
|--------|------------|
| `nav.source_path` | frozen snapshot of what arrived |
| `nav.path` | the working copy, mutated in place |
| `nav.normalized_path` | the working copy as a shape - ids back as `'ref'` |

`lux.route.normalized_path` is the cursor-relative version.

The `app/views/**/ref.haml` convention keeps working unchanged: `auto_render`
resolves templates from `normalized_path`, so `/boards/abc123/edit` still renders
`app/views/boards/ref/edit.haml`.

If you were matching on the placeholder form:

```ruby
# before
nav.pathname(ends: 'ref')

# after - by shape
nav.normalized_path.last == 'ref'

# after - by type, which also excludes a literal /ref segment
nav.path.last.is_a?(Lux::Application::Nav::Base)
```

### `:ref` matches by type, not by spelling

Everywhere the router takes a segment pattern - `filter :ref`, `map 'ref'`,
`match?(:ref)`, `start_with?(:spaces, :ref)` - `:ref` now means "a segment the
classifier recognised". A URL segment literally spelled `ref` is no longer one,
and nothing matches `:ref` until a classifier has run.

```ruby
# /spaces/ref      -> filter :ref no longer matches
# /spaces/abc123   -> filter :ref matches, once nav.ref has run
```

Make sure `nav.ref` runs in a router before-filter ahead of any controller that
uses `filter :ref`. `nav.load_models` (db plugin) already does this for you.

If you genuinely need to route a literal `/ref` URL, the pattern is now
unreachable - rename the segment.

Note this is only the *pattern* side. A `:name` placeholder inside an absolute
`capture` pattern is still just a capture name, so `map '/boards/:ref/edit'`
binds whatever segment is in that position, as before.

### `nav.refs` is derived

It is computed from `nav.path` on every call. Pushing to it does nothing.

### Comparisons are one-way

`String#==` rejects a non-String, and a ref segment deliberately does not define
`to_str`. Keep the segment on the left, or compare `.value`:

```ruby
nav.path[1] == 'abc123'     # true
'abc123' == nav.path[1]     # false
nav.path[1].value           # 'abc123'
```

## What you get

### Classify without a block

The format knows what it looks like, so the router does not have to restate it:

```ruby
# before
nav.path(:ref) { |el| Lux::Utils::Ref.is?(el) ? el : nil }

# after - one line, no rule
nav.map_path
```

The block form still works, and is still the way to go when the id has to be
extracted from a bigger segment:

```ruby
nav.map_path { |el| el.split('-').last.then { |p| Lux::Utils::Ref.is?(p) ? p : nil } }
```

It is now yielded `(segment, list_so_far)`, so a rule can look at what sits to
its left. One-arg blocks are unaffected - the segment is still the first
argument.

```ruby
# only treat an id as one when it follows /boards
nav.map_path { |el, list| Lux::Utils::Ref.is?(el) && list.last == 'boards' ? el : nil }
```

### `path_before`

Each ref knows the segment that preceded it when it was classified - the
resource name in `/boards/<ref>`. `nil` at position 0.

```ruby
# GET /orgs/<r1>/users/<r2>
nav.path[1].path_before   # 'orgs'
nav.path[3].path_before   # 'users'
```

### The id format is declared once, in config

This is the part that matters if you ever change id shape. `Lux.config.ref_format`
names the format, and **everything that needs to know what an id looks like
resolves through it**: the router (`nav.map_path`), the `:ref` column type,
`Lux::Utils::Ref` (which mints model primary keys), and `nav.load_models`.

```yaml
# config/config.yaml
default:
  ref_format: uuid7
```

That one line moves the router, the primary-key generator and the column
definition together. Previously the format was hardcoded in four places and only
the router was reachable from app code, so an app switching id shape got
mismatched primary keys and a wrong-width column.

Ships with two formats:

| name | shape | column |
|---|---|---|
| `:string` (default) | 16-char lowercase alnum - what every lux app uses today | `varchar(20)` |
| `:uuid7` | RFC 9562 UUIDv7, time-ordered | `varchar(36)` |

Attributes parameterise a format, so a variant does not need a subclass:

```yaml
default:
  ref_format:
    string:
      length: 26
      upcase: true
```

Or register a named variant of your own once, at boot:

```ruby
Lux::Application::Nav::Base.register :app_ref, Lux::Application::Nav::RefString,
  length: 26, upcase: true
Lux.config.ref_format = :app_ref
```

### Ref formats are classes

`Lux::Application::Nav::Base` is the contract: instance `generate`, `valid?` and
`db_limit`. Subclass it for an id shape the built-ins do not cover, register it,
and name it in config.

```ruby
class Lux::Application::Nav::RefNumeric < Lux::Application::Nav::Base
  def generate;  with(SecureRandom.random_number(10**12).to_s); end
  def valid?;    @value.to_s.match?(/\A\d+\z/);                 end
  def db_limit;  20;                                            end
end

Lux::Application::Nav::Base.register :numeric, Lux::Application::Nav::RefNumeric
```

A one-off override at the call site still works, without registering:

```ruby
nav.map_path Lux::Application::Nav::RefUuid7
nav.map_path :string, upcase: true
```

## Moved out of the db plugin

`plugins/db/lib/ref.rb` and `plugins/db/lib/ref_type.rb` are gone. Nothing you
call changed name, but if you required either file directly, update the path:

| was | now |
|-----|-----|
| `Lux::Utils::Ref.generate` / `.is?` | [`lib/lux/utils/ref.rb`](../lib/lux/utils/ref.rb) (core) |
| `Lux::Type::RefType` | [`lib/lux/type/types/ref_type.rb`](../lib/lux/type/types/ref_type.rb) (core) |
| `Nav#load_models`, `Ref.register` / `.klass` / `.load` / `.models` / `.public_link` | `plugins/db/ext/nav_models.rb` (still the plugin - needs Sequel) |

The format now has one definition, so the router, the `:ref` column type and
model primary keys cannot drift apart. `RefType` previously accepted `/^\w+$/`,
which let uppercase and `_` through; it is now the same rule as everything else.

Two behaviour notes:

* `is?` now returns a real boolean and returns `false` on `nil` instead of
  raising `NoMethodError`.
* `generate`'s unused `uppercase:` option is gone, along with `MIXEDCASE_KEYS`.

The model registry (`register`, `klass`, `load`, `models`, `public_link`) needs
Sequel and stays in the db plugin.
