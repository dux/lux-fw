# Lux::Utils

Single-file utility modules that don't justify their own subsystem. Pure
helpers - no request state, no boot ordering, callable from anywhere.

`Lux.crypt` shims `Lux::Utils::Crypt`. The other utilities are accessed
via their full namespace, or through monkey-patches on stdlib classes
(`String#to_b`, `Hash#to_jsonp`, `Time#short`, etc.).

## Members

| Constant | File | Purpose |
|----------|------|---------|
| `Lux::Utils::Crypt`         | `crypt.rb`           | JWT-based encrypt/decrypt + hashes + uid |
| `Lux::Utils::StringBase`    | `string_base.rb`     | base-N integer encoding (short/medium/long key sets) |
| `Lux::Utils::TimeDifference`| `time_difference.rb` | humanise relative time ("3 minutes ago") |
| `Lux::Utils::Boolean`       | `boolean.rb`         | string -> boolean parser, mixed into TrueClass/FalseClass |
| `Lux::Utils::Json`          | `json.rb`            | `to_jsons` / `to_jsonp` / `to_jsonc`, mixed into Hash/Array |
| `Lux::Utils::TimeOptions`   | `time_options.rb`    | `short` / `long` date formatters, mixed into Time/Date/DateTime |
| `Lux::Utils::HtmlTag`       | `html_tag/`          | tag-based HTML builder DSL (vendored, rewritten); top-level `HtmlTag` kept as alias |

Two more live in the db plugin (same namespace, plugin-coupled location):

| Constant | File |
|----------|------|
| `Lux::Utils::Ref`            | `plugins/db/lib/ref.rb` |
| `Lux::Utils::PaginatedArray` | `plugins/db/ext/paginate.rb` |

## Full example

### Crypt

```ruby
# Requires ENV['SECRET'] or Lux.config.secret.

# --- JWT encrypt / decrypt ---------------------------------------------
Lux.crypt.encrypt('payload')                          # JWT, no expiry
Lux.crypt.encrypt('payload', ttl: 1.hour)             # JWT, 1h expiry
Lux.crypt.encrypt('payload', password: 'extra')       # JWT, extra password layer
Lux.crypt.decrypt(token)                              # raises on bad token / expired
Lux.crypt.decrypt(token, unsafe: true)                # returns nil instead of raising

# --- short reversible tokens (8-char check + base64, with ttl) ---------
short = Lux.crypt.short_encrypt('data')               # default 1.day ttl
Lux.crypt.short_decrypt(short)                        # 'data'

# --- hashes (mixed with Lux.config.secret) -----------------------------
Lux.crypt.sha1('x')                                   # full hex
Lux.crypt.sha1s('x')                                  # shorter base-36
Lux.crypt.md5('x')

# --- random -----------------------------------------------------------
Lux.crypt.uid                                         # 32-char lowercase alphanumeric
Lux.crypt.uid(8)                                      # 8 chars
Lux.crypt.random(16)                                  # 16 chars from a-z0-9 (no ambiguous)

# --- bcrypt -----------------------------------------------------------
hash  = Lux.crypt.bcrypt('password')                  # hash a password
match = Lux.crypt.bcrypt('password', hash)            # boolean check

# --- ROT13+base64 (NOT crypto - just obfuscation) ----------------------
Lux.crypt.simple_encode('hi')
Lux.crypt.simple_decode('uv')

# --- per-request variants (IP-bound, 10-minute default) ----------------
Lux.current.encrypt('data')                           # password defaults to caller IP
Lux.current.decrypt(token)                            # only decryptable by same IP
```

### StringBase

```ruby
# default short keys (lowercase consonants + digits, multiplier 99)
Lux::Utils::StringBase.encode(12345)                  # "bcm..." short string
Lux::Utils::StringBase.decode('bcm...')               # 12345

# explicit key sets
Lux::Utils::StringBase.medium.encode(42)              # full alphanumeric
Lux::Utils::StringBase.long.encode(42)                # case-sensitive

# random
Lux::Utils::StringBase.medium.rand(16)                # 16-char random
Lux::Utils::StringBase.uid                            # time-based 16-char id

# Integer / String monkey-patches (encode/decode for url slugs)
12345.string_id                                       # encoded
"some-title-bcm123".string_id                         # extracts + decodes

# extract id from slug
Lux::Utils::StringBase.short.extract("some-title-bcm123")
```

### TimeDifference

```ruby
Lux::Utils::TimeDifference.new(Time.now - 180).humanize   # "before 3 minutes"
Lux::Utils::TimeDifference.new(Time.now, Time.now + 7200).humanize  # "in 2 hours"

# Date class -> "today" if same day
Lux::Utils::TimeDifference.new(Date.today, Date.today, Date).humanize  # "today"

# Time.ago wrapper (in lib/overload/time.rb) uses it internally
Time.ago(some_time)
```

### Boolean

```ruby
Lux::Utils::Boolean.parse('yes')     # true
Lux::Utils::Boolean.parse('0')       # false
Lux::Utils::Boolean.parse('foo')     # nil (unknown)

# TrueClass / FalseClass / Numeric / Object monkey-patches
true.to_i                            # 1
false.to_i                           # 0
3.to_b                               # true (Numeric > 0)
'on'.to_b                            # true (Object#to_b -> Boolean.parse)
```

### Json

```ruby
data = { user: { name: 'Dux' } }
data.to_jsons        # pretty in dev mode, compact in prod
data.to_jsonp        # always pretty
data.to_jsonp(true)  # pretty + colorise keys (terminal)
data.to_jsonc        # compact, unquoted keys (for embedding in JS)
```

### HtmlTag

```ruby
# Builder form (returns the rendered HTML string)
HtmlTag.div(class: 'box') do |n|
  n.h1 'Title'
  n.p  'Body'
end
# => "<div class=\"box\"><h1>Title</h1><p>Body</p></div>"

# Explicit render entry (when you want a non-bareword tag name)
HtmlTag.call(:ul) do |n|
  n.li 'one'
  n.li 'two'
end

# Class mixin - imports `tag` without pulling the rest of the module
class Card
  HtmlTag.mixin(self)

  def render
    tag.div(class: 'card') { tag.h2 'Hello' }
  end
end

# include HtmlTag - same `tag` helper, full module included
class Widget
  include HtmlTag
end

# Hash#tag / String#tag (lib/overload/hash.rb, lib/overload/string.rb)
{ class: 'btn' }.tag(:button, 'Save')   # '<button class="btn">Save</button>'
'hello'.tag(:span, class: 'lead')       # '<span class="lead">hello</span>'

# `_klass` div shortcut: tag name starting with `_` -> <div class="klass">.
# `__` separates classes, remaining `_` become `-`.
tag._search_filter            # <div class="search-filter"></div>
tag._card__lead { 'x' }       # <div class="card lead">x</div>

# Register a custom tag
HtmlTag.define :foo
HtmlTag.define :hr2, empty: true

# Pretty output (off by default)
HtmlTag::OPTS[:format] = true
```

Signature is uniform across every entry point:

```
tag(name, inner = nil, **attrs, &block)
```

* `inner` is the text/value placed between the tags (overridden by `&block`).
* `attrs` are always kwargs - the old `div 123, class: :foo` arg-order swap is gone.
* Inside a `&block`, unknown methods flow to the host (cell/controller), and host
  `@ivars` are visible. Use `this` / `context` / `parent` for an explicit host handle.

### TimeOptions

```ruby
Time.now.short       # "2026-05-22"  (per Lux.config[:date_format] or yyyy-mm-dd)
Time.now.long        # "2026-05-22 14:33"
Time.now.short(true) # force default format, ignore config

# Date / DateTime also get .short / .long
```

## Notes

* `Lux.crypt.sha1` mixes in `Lux.config.secret`, so digests are
  domain-secret. They are *not* a portable hash of the input.
* `Lux::Utils::Boolean.parse` returns `nil` for unknown input (not false).
  Use this when you need to distinguish "explicitly false" from "missing".
* Inside `lib/overload/{boolean,json,time}.rb` the stdlib reopens
  (`class Hash`, `class Time`, etc.) live separately and `require_relative`
  these util modules. Loading those overloads pulls in the corresponding
  utility automatically.

## See also

* [`../current/README.md`](../current/README.md) - `Lux.current.encrypt/decrypt` (per-request variants)
* [`../../../plugins/db/lib/ref.rb`](../../../plugins/db/lib/ref.rb) - `Lux::Utils::Ref`
* [`../../../plugins/db/ext/paginate.rb`](../../../plugins/db/ext/paginate.rb) - `Lux::Utils::PaginatedArray`
