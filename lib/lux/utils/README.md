# Lux::Utils

Single-file utility modules that don't justify their own subsystem. Pure
helpers - no request state, no boot ordering, callable from anywhere.

`Lux.crypt` shims `Lux::Utils::Crypt`. The other utilities are accessed
via their full namespace, or through monkey-patches on stdlib classes
(`Object#is_true?`, `Hash#to_jsonp`, `Time#short`, etc.).

Optional gems: `Lux.crypt.bcrypt` needs `bcrypt` and time zones (`Time#short`
with `var[:time_zone]`) need `tzinfo` in the app Gemfile; both load lazily.

## Members

| Constant | File | Purpose |
|----------|------|---------|
| `Lux::Utils::Crypt`         | `crypt.rb`           | JWT encrypt/decrypt, AES-GCM seal/unseal, hashes, uid |
| `Lux::Utils::Markdown`      | `markdown.rb`        | Markdown -> HTML (CommonMark + GFM) via Commonmarker |
| `Lux::Utils::StringBase`    | `string_base.rb`     | base-N integer encoding (short/medium/long key sets) |
| `Lux::Utils::TimeDifference`| `time_difference.rb` | humanise relative time ("3 minutes ago") |
| `Lux::Utils::Boolean`       | `boolean.rb`         | string -> boolean parser, mixed into TrueClass/FalseClass |
| `Lux::Utils::Json`          | `json.rb`            | `to_jsons` / `to_jsonp` / `to_jsonc`, mixed into Hash/Array |
| `Lux::Utils::TimeOptions`   | `time_options.rb`    | `short` / `long` date formatters, mixed into Time/Date/DateTime |
| `Lux::Utils::HtmlTag`       | `html_tag/`          | tag-based HTML builder DSL (vendored, rewritten); top-level `HtmlTag` kept as alias |
| `Lux::Utils::Url`           | `url.rb`             | URL parser/builder with path attrs, locale, qs, pqs (vendored from `lux-url` gem); top-level `Url` kept as alias; browser twin is `$.url` |
| `Lux::SafeString`           | `safe_string.rb`     | markup string templates print as is (`html_safe?`); required by `loader.rb` right after `lib/overload/string.rb`, see [Output escaping](../../overload/README.md#output-escaping) |

One more constant lives in the db plugin outright, since it needs Sequel:

| Constant | File |
|----------|------|
| `Lux::Utils::PaginatedArray` | `plugins/db/lib/ext/paginate.rb` |

## Full example

### Crypt

```ruby
# Requires ENV['SECRET'] or Lux.config.secret.

# --- JWT encrypt / decrypt ---------------------------------------------
Lux.crypt.encrypt('payload')                          # JWT, no expiry
Lux.crypt.encrypt('payload', ttl: 1.hour)             # JWT, 1h expiry (standard `exp` claim, JWT.decode enforces it)
Lux.crypt.encrypt('payload', password: 'extra')       # JWT, extra password layer
Lux.crypt.decrypt(token)                              # raises on bad token; JWT::ExpiredSignature once expired
Lux.crypt.decrypt(token, unsafe: true)                # returns nil instead of raising

# --- authenticated encryption (AES-256-GCM): unreadable + tamper-proof ---
t = Lux.crypt.seal({ 'user_ref' => 'x' }, ttl: 1.day, purpose: 'session')
Lux.crypt.unseal(t, purpose: 'session')   # => { 'user_ref' => 'x' }; nil if forged/expired/other purpose

# --- short reversible tokens (16-char HMAC check + base64, with ttl) ----
short = Lux.crypt.short_encrypt('data')               # default 1.day ttl
Lux.crypt.short_decrypt(short)                        # 'data'

# --- hashes ------------------------------------------------------------
Lux.crypt.sha1('x')                                   # HMAC-SHA1 keyed with the secret, full hex
Lux.crypt.sha1s('x')                                  # shorter base-36, NOT keyed (plain SHA1)
Lux.crypt.md5('x')                                    # HMAC-MD5 keyed with the secret

# --- random -----------------------------------------------------------
Lux.crypt.uid                                         # 32-char lowercase alphanumeric
Lux.crypt.uid(8)                                      # 8 chars
Lux.crypt.random(16)                                  # 16 chars from a-z0-9 (no ambiguous)

# --- bcrypt (needs the bcrypt gem in the app Gemfile) ------------------
hash  = Lux.crypt.bcrypt('password')                  # hash a password
match = Lux.crypt.bcrypt('password', hash)            # boolean check

# --- ROT13+base64 (NOT crypto - just obfuscation) ----------------------
Lux.crypt.simple_encode('hi')
Lux.crypt.simple_decode('uv')

# --- per-request variants (IP-bound, 10-minute default) ----------------
Lux.ctx.encrypt('data')                           # password defaults to caller IP
Lux.ctx.decrypt(token)                            # only decryptable by same IP
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

# lib/overload: Object#is_true? and the top-level Boolean alias
'on'.is_true?            # true  (Boolean.parse(self) == true)
true.is_a?(Boolean)      # true  (TrueClass/FalseClass include Lux::Utils::Boolean)
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

# Class mixin - defines `#tag` on the class itself, so it overrides a `tag` the
# class already has (e.g. one from `delegate :tag`); `include HtmlTag` would not
class Card
  HtmlTag.mixin(self)

  def render
    tag.div(class: 'card') { h2 'Hello' }
  end
end

# include HtmlTag - same `tag` helper
class Widget
  include HtmlTag
end

# Hash#tag / String#tag (lib/overload/hash.rb, lib/overload/string.rb)
{ class: 'btn' }.tag(:button, 'Save')   # '<button class="btn">Save</button>'
'hello'.tag(:span, class: 'lead')       # '<span class="lead">hello</span>'
{ class: nil, hidden: false }.tag(:i)  # '<i hidden="false"></i>' - nil attrs are omitted, false renders

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
* Inside a `&block`, unknown methods flow to the host (cell/router), and host
  `@ivars` are visible. Use `this` / `context` / `parent` for an explicit host handle.

### Url (`lib/lux/utils/url.rb`)

Vendored from the old `lux-url` gem. Source of truth for URL parse/build on
the server. Same vocabulary as the browser port `$.url`
([`plugins/web_common/.../dollar/dollar_url.js`](../../../plugins/web_common/assets/js/dollar/dollar_url.js)):
`qs`, `pqs` / `path_qs`, path prefix `/:a:b`, locale segment, subdomain, fragment.

Entry points: `Lux::Utils::Url` (canonical), top-level `Url` alias, `Lux.url`,
`Lux.ctx.url`, class methods on `Url` that rewrite the current request.

```ruby
# Build from a string
u = Lux.url('https://sub.lvh.me:3000/:a:b-2/some/path/menu:demo?foo=bar')
u[:foo]        # 'bar'  (qs shortcut)
u[:menu]       # 'demo' (falls back to path qs)
u.path         # '/:a:b-2/some/path/menu:demo'
u.path_qs      # { 'menu' => 'demo' }
u.qs           # { 'foo' => 'bar' }
u.path_prefix  # ['a', 'b-2']

# Mutate (chainable)
u.qs(:foo, 'baz').delete(:menu).hash('top')   # delete only touches ?qs; menu is path qs
u.to_s         # 'https://sub.lvh.me:3000/:a:b-2/some/path/menu:demo?foo=baz#top'
u.pqs(:tag, 'x')  # writes path qs and clears matching ?tag= if present

# Current request handles
Lux.ctx.url            # Lux::Utils::Url of the current request
Lux.url                    # same (no-arg form delegates to Lux.ctx.request.url)
Lux.url.qs(:page, 2).to_s  # rewrite current url

# Class methods still operate on the current request
Url.escape('a b/c')        # 'a%20b%2Fc' (space -> %20, same as String#escape; nil-safe)
Url.unescape('a+b%20c')    # 'a b c'     (reads + and %20 as a space)
Url.split_host('a.example.co.uk')  # ['a', 'example.co.uk'] - the one domain parser; Router::Nav uses it too
Url.locale('fr')           # swap locale prefix on current url, return relative
Url.toggle(:sort, 'asc')   # set qs unless equal, else clear (for filter UIs)
Url.qs(:page, 2)           # set qs on current request, return relative string
Url.pqs(:tag, 'dux')       # path qs /tag:dux on current request, relative
```

Specs: `spec/lux_tests/url_spec.rb`.

### TimeOptions

```ruby
Time.now.short       # "2026-05-22"  (per Lux.config[:date_format] or yyyy-mm-dd)
Time.now.long        # "2026-05-22 14:33"
Time.now.short(true) # force default format, ignore config

# Date / DateTime also get .short / .long
# var[:time_zone] needs the tzinfo gem in the app Gemfile
```

## Notes

* `Lux.crypt.sha1` / `md5` are HMACs keyed with `Lux.config.secret`, so digests are
  domain-secret. They are *not* a portable hash of the input; use `sha1s` or `Digest` for that.
* `Lux::Utils::Boolean.parse` returns `nil` for unknown input (not false).
  Use this when you need to distinguish "explicitly false" from "missing".
* Inside `lib/overload/{boolean,json,time}.rb` the stdlib reopens
  (`class Hash`, `class Time`, etc.) live separately and `require_relative`
  these util modules. Loading those overloads pulls in the corresponding
  utility automatically.

## See also

* [`../context/README.md`](../context/README.md) - `Lux.ctx.encrypt/decrypt` (per-request variants)
* [`url.rb`](./url.rb) - `Lux::Utils::Url` (server); browser twin [`dollar_url.js`](../../../plugins/web_common/assets/js/dollar/dollar_url.js) (`$.url`)
* [`../ref/README.md`](../ref/README.md) - `Lux::Ref`, the app's id format
* [`../../../plugins/db/lib/ext/paginate.rb`](../../../plugins/db/lib/ext/paginate.rb) - `Lux::Utils::PaginatedArray`
