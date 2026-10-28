# Lux::Ref

What an id looks like, app-wide.
`Lux.config.ref_format` names one format; `nav.map_path`, the `:ref` column type (`Lux::Type::RefType`), model primary keys and `nav.load_models` all resolve through it, so they cannot drift apart.

## Canonical example

```ruby
Lux.config.ref_format = :string        # default; or :uuid7, :slug, { string: { length: 26 } }

Lux::Ref.generate                      # 'k3p9x2mq7wd1nb84'
Lux::Ref.is?('k3p9x2mq7wd1nb84')       # true

# in a router before filter / route block
nav.map_path                           # GET /boards/k3p9x2mq7wd1nb84/edit
nav.path                               # ['boards', 'ref', 'edit']   - the route shape
nav.path[1].value                      # 'k3p9x2mq7wd1nb84'
nav.ref                                # 'k3p9x2mq7wd1nb84'
nav.pathname                           # '/boards/k3p9x2mq7wd1nb84/edit'
```

## API

|Call|What it does|
|---|---|
|`Lux::Ref.generate(*args)`|fresh id in the app format (`Short` takes a length)|
|`Lux::Ref.is?(text)`|does `text` look like an id in the app format|
|`Lux::Ref.build(value = nil, format: nil)`|format instance (app format unless `format:`)|
|`Lux::Ref.resolve(format)`|registered name, `{ name => attrs }` or a `Base` subclass -> `[klass, attrs]`|
|`Lux::Ref.register(name, klass, **attrs)`|name a format; attrs are its defaults|
|`Lux::Ref.models`|db plugin: every Sequel model with an `abbr`|

## Formats

|Name|Class|Id|
|---|---|---|
|`:string`|`Lux::Ref::Short`|16 chars `a-z0-9` (`length:`, `upcase:` attrs)|
|`:uuid7`|`Lux::Ref::Uuid7`|time-ordered UUID v7|
|`:slug`|`Lux::Ref::Slug`|a `Short` id at the end of a slug: `dino-reic-<ref>`, or bare|

A format is a `Lux::Ref::Base` subclass with `valid?`, `generate`, `db_limit` and optionally `extract(segment)` - the id a URL segment carries, or nil.
`nav.map_path` with no block asks `extract`.

```ruby
# /admin/users/ref-ab12 -> 'ab12', on top of the slug rule
class SlugRef < Lux::Ref::Slug
  def extract segment
    prefix, id = segment.split('-').last(2)
    super || (prefix == 'ref' ? id : nil)
  end
end

Lux::Ref.register :slug_ref, SlugRef
Lux.config.ref_format = :slug_ref
```

## Rules

* A format instance is also the `nav.path` element: a frozen String reading `'ref'`, with the id on `.value`.
  `map :ref` matches it by type, captures bind `.value`, and `auto` finds `boards/ref/edit.haml`.
  Test with `is_a?(Lux::Ref::Base)`; a URL segment spelled `ref` is a plain String.
* Read ids with `nav.ref` / `nav.refs` / `.value`, never by reading the text of `nav.path[i]`.
* `nav.source_path` keeps the URL as it arrived, with ids as text.
* Never name a class `String` inside `module Lux`; the 16-char format is `Short`, registered as `:string`.

## See also

* [`../router/lib/nav.rb`](../router/lib/nav.rb) - `nav.map_path`, `nav.ref`, `nav.path`
* [`../type/types/ref_type.rb`](../type/types/ref_type.rb) - the `:ref` column type
* [`../../../plugins/db/lib/ext/nav_models.rb`](../../../plugins/db/lib/ext/nav_models.rb) - `Lux::Ref.models` + `Nav#load_models`
