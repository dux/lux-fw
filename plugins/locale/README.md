# Lux::Locale

Small, namespaced translation lookup. Flat text files on disk, dotted
keys, two extension points for dynamic sources. No external i18n gem.

## Small example

```ruby
Lux.locale.default   = :en
Lux.locale.available = %i[en de]

Lux.locale.t('users.welcome', name: 'Joe')        # "Hi Joe"
Lux.locale.set('users.welcome', 'Hi %{name}', locale: :en)
Lux.locale.t                                       # :en (current or default)
```

## Full example

```ruby
# --- boot ---

Lux.locale.default   = :en
Lux.locale.available = %i[en de hr]
Lux.locale.dir       = Pathname.new('./config/locales')   # default

# --- lookup ---

Lux.locale.t('users.welcome', name: 'Joe')                # "Hi Joe"
Lux.locale.t('users.welcome', name: 'Joe', locale: :de)   # force locale
Lux.locale.t('users.missing', fallback: 'Hi there')       # explicit fallback
Lux.locale.t('users.unknown')                             # "[users.unknown]"

# --- write ---

Lux.locale.set('users.farewell', 'Bye %{name}', locale: :en)

# --- dynamic namespace ---

# subkey is everything after the namespace.
# Non-nil wins; nil falls through to the file for that namespace.
Lux.locale.namespace(:product) do |subkey, locale|
  Product[subkey.split('.').last]&.translate(locale)
end

# --- global hooks ---

# Short-circuit any lookup. Return nil to fall through.
Lux.locale.before_get { |locale, key| MyTracker.incr(key); nil }

# Transform every value being saved. Return nil to leave untouched.
Lux.locale.before_set { |locale, key, v| v.to_s.strip }

# --- templates ---

# Auto-exposed in Lux::Template::Helper
# = t('users.welcome', name: @user.name)
```

## Large texts as files

Multi-paragraph content (terms, legal pages, long emails) doesn't fit the
one-line flat format. Prefix the key with a file extension to read a whole
file instead:

```ruby
Lux.locale.t('md:legal.terms')               # current locale
Lux.locale.t('md:legal.terms', locale: :de)  # force locale
```

The prefix is the file extension. The path's leading segments are folders
and the last is the filename, rooted at `dir/<ext>`:

```
t('md:service')           ->  ./config/locales/md/service.<locale>.md
t('md:legal.terms')       ->  ./config/locales/md/legal/terms.<locale>.md
t('html:email.welcome')   ->  ./config/locales/html/email/welcome.<locale>.html
```

The entire file is returned raw - no markdown rendering. Render at the call
site (e.g. the `<s-markdown>` web component):

```ruby
# = t('md:service').tag('s-markdown')
```

Same default-locale fallback, `[md:service]` missing marker and `%{var}`
interpolation as the line lookup. Unlike line keys, a single segment
(`'md:service'`) is allowed - the namespacing dot is not required.

### Localized files alongside templates

To keep a localized file next to the templates instead of under the locale
dir, use a `/`-prefixed key. It is rooted at the views dir and the locale is
inserted before the final extension:

```ruby
Lux.locale.t('/main/legal/policy.html', language: :en)
# -> app/views/main/legal/policy.en.html
```

```
t('/main/legal/policy.html')  ->  app/views/main/legal/policy.<locale>.html
t('/emails/welcome.md')       ->  app/views/emails/welcome.<locale>.md
```

`language:` is accepted as an alias for the `locale:` keyword. The views root
follows `Lux.current.var.views_root` (default `./app/views`). Same fallback,
marker and interpolation rules as above.

## On-disk format

One flat text file per `(namespace, locale)` at
`./config/locales/<namespace>/<locale>.txt`. One entry per line,
`key: value`:

```
profile.title: Profile
welcome: Hi %{name}
```

* Keys never contain spaces or colons.
* Lines are re-sorted alphabetically on every `set`.
* Blank lines and lines without `:` are ignored on read.
* No nesting on disk - the dotted key is the storage key.

## Lookup chain

For `Lux.locale.t('users.welcome', name: 'Joe')` in current locale `:de`:

1. `before_get.call(:de, 'users.welcome')` - non-nil wins.
2. `namespace(:users)` handler called with `('welcome', :de)` - non-nil wins.
3. `store.get(:de, :users, 'welcome')` if a store is configured.
4. File `./config/locales/users/de.txt`, line `welcome: ...`.
5. Same chain in `default` locale (skipped if already default).
6. `fallback:` arg.
7. `"[users.welcome]"` as a visible-but-non-fatal marker.

Interpolation (`%{name}`) runs on the resolved string at the end.

## API

| call | returns |
|------|---------|
| `default=`, `default` | symbol |
| `available=`, `available` | array of symbols |
| `dir=`, `dir` | Pathname |
| `store=`, `store` | any object responding to `.get(locale, ns, sub)` / `.set(locale, ns, sub, value)`; replaces the file backend for reads (after namespace handler) and writes |
| `current` | symbol (validated against `available`) |
| `force?` | bool; the active `localized` scope required the prefix |
| `path(value, locale:)` | locale-prefixed path from a String or a `path`/`to_path` object; default locale stays bare unless forced |
| `seo_links(value, base:)` | canonical + per-locale hreflang + x-default link attribute hashes for a locale-free path |
| `geo_locale(country)` | available locale for an IP-geo country code (CF-IPCountry), else nil |
| `detect` | symbol; peels `/xx` off `nav.path`, stores it in the session, sets `Lux.current.locale` |
| `t(key, locale:, fallback:, **vars)` | string |
| `set(key, value, locale:)` | the stored value |
| `namespace(name) { \|subkey, locale\| ... }` | registers handler |
| `before_get { \|locale, key\| ... }` | registers hook |
| `before_set { \|locale, key, value\| ... }` | registers hook |
| `reload!` | drops the in-process file cache |

## URL locale prefix

Two pieces work together:

* `Lux.locale.detect` peels a leading `/xx` (or `/xx-YY`) off the request
  path, remembers it in the session, and sets `Lux.current.locale`. Call it
  once in a `before` filter; without it the prefix is treated as an ordinary
  path segment.
* The `localized` routing directive enforces the URL shape for a route
  scope, at the point it is declared. The request's state is kept on
  `Lux.current[:locale_localized]` and `Lux.current[:locale_force]`.

```ruby
Lux.app do
  before { Lux.locale.detect }

  map 'admin' do                 # /en/admin -> /admin
    localized(false) { call 'admin#call' }
  end

  localized force: true do       # / and /users -> /<current>, /<current>/...
    root 'main'
    map 'users'
  end
end
```

| directive | no prefix | with prefix |
|-----------|-----------|-------------|
| `localized` | pass | pass; the default locale redirects to the bare path |
| `localized force: true` | redirect to `/<current>/<path>` | pass |
| `localized(false)` | pass | redirect to `<path>` |

With `localized` (not forced) the default locale is canonical without a
prefix, so `/en/service` (default `:en`) redirects to `/service`; a non-default
prefix such as `/de/service` passes through. `force: true` keeps the prefix,
default included.

An un-localized scope must be declared before a `force: true` one: the first
dispatch ends routing, and `force` redirects as soon as it is reached. `force`
uses the current locale, so a `de` visitor hitting `/users` lands on
`/de/users`.

### First-visit geo redirect

A visitor who arrives with no `/xx` prefix and no remembered choice can be sent
to their country's locale in one hop. A true `localized` scope reads the country
from the request - `CF-IPCountry` (Cloudflare) or `X-Geo-Country` / `X-Country` -
maps it through `LANGUAGES`, and redirects only when it lands on a non-default
available locale. The choice is recorded in the session, so it fires once and
never fights a visitor's own choice. `geo:` defaults to `true`; pass
`geo: false` to keep a scope localized without the redirect.

```ruby
Lux.app do
  before { Lux.locale.detect }

  localized true do     # a German visitor to / -> 302 /de
    call 'promo#auto'
  end
end
```

`Lux.locale.geo_locale('DE')` returns `:de` (`nil` for unknown codes such as
`XX`/`T1`, and for countries that map to the bare default). Since the redirect
is IP-based and temporary (302), keep the canonical/hreflang links so crawlers
still see every locale - see [SEO links](#seo-links).

### Path helper

`Lux.locale.path` builds a locale-prefixed path with the same convention - the
default locale stays bare unless the request is forced. It takes a String, or
any object that knows its own path (`object.path`, else `object.to_path`). The
`lux.lpath` shortcut (the current-thread pointer) and the `lpath` template
helper both delegate to it:

```ruby
Lux.locale.path('/service')              # "/service", or "/en/service" when forced
Lux.locale.path('/service', locale: :de) # "/de/service"
Lux.locale.path('/')                     # "/" or "/de"
Lux.locale.path(user)                    # user.path, locale-prefixed

lux.lpath('/service')                    # current-thread shortcut
lpath('/service')                        # template helper
```

`Lux.locale.force?` reads the current request's flag. The state lives on
`Lux.current[:locale_localized]` and `Lux.current[:locale_force]`.

### SEO links

For a localized site, `seo_links` returns the canonical and hreflang tags a
crawler needs: a self-canonical for the current locale, one `alternate` per
available locale, and `x-default` for the default. Pass a locale-free path and
the absolute origin; the tags are plain hashes a view renders as-is.

```haml
- Lux.locale.seo_links(here, base: 'https://example.com').each do |link|
  %link{ link }
```

```html
<link href="https://example.com/de/docs" rel="canonical">
<link href="https://example.com/docs" hreflang="en" rel="alternate">
<link href="https://example.com/de/docs" hreflang="de" rel="alternate">
<link href="https://example.com/docs" hreflang="x-default" rel="alternate">
```

## DB-backed store

When `ApplicationModel` is defined, the plugin auto-loads `LuxTranslation`
and sets it as the store. Each translation is one row keyed by
`(locale, namespace, key)`. `Lux.locale.t` reads from the table, and
`Lux.locale.set` upserts. Run `rake db:am` to materialise the table.

Direct calls:

```ruby
LuxTranslation.get(:en, :users, 'welcome')   # explicit ns + key
LuxTranslation.get(:en, 'users.welcome')     # full dotted key, split on first '.'
LuxTranslation.set(:en, :users, 'welcome', 'Hi %{name}')
```

To keep the file backend in a DB-enabled app, set `Lux.locale.store = nil`
after the plugin loads.

`current` reads `Lux.current.locale` (set by `Lux.locale.detect` from the URL
prefix). Falls back to `default`. Unknown locale -> `Lux::Locale::Unknown`.

## Translated columns (`pg_translations`)

Ships with this plugin: a Sequel plugin that turns any `_t` JSONB column into
a localized reader. Resolves through `Lux.locale.current` / `Lux.locale.default`,
so it only works where the locale plugin is loaded.

Apply per-model:

```ruby
class Product < ApplicationModel
  plugin :pg_translations
end
```

```ruby
# schema:  name_t  :jsonb
record.name_t      # { "en" => "Hello", "hr" => "Bok" }  (raw hash)
record.name        # "Hello"  (current locale, fallback to default)
```

* `Model.t_columns` lazily scans `db_schema` for `_t` columns.
* The first read of `name` (for `name_t`) defines a real reader method on the
  class via `method_missing` - no `method_missing` cost on later calls.
* Resolution: `data[Lux.locale.current]` if present (non-blank), else
  `data[Lux.locale.default]`, else `nil`. Empty string counts as missing.

This is the read side. The matching write side is the `:translated` schema type
(`Lux::Type::TranslatedType`), which coerces incoming values into the same
`{ locale => text }` jsonb shape - a bare string lands under `Lux.current.locale`,
and editing a single locale drops the stale siblings so they can be re-translated.
See [`../../lib/lux/type/README.md`](../../lib/lux/type/README.md).

## Notes

* The in-process file cache invalidates on file `mtime` change, so dev
  edits show up without restart or reloader wiring.
* `before_get` returning `nil` falls through to the normal chain. Same
  for `before_set` - returning `nil` leaves the value untouched.
* Single-segment keys (`'hi'`) raise `ArgumentError`. Namespace is
  mandatory so files split predictably.

## See also

* [`../../lib/lux/current/README.md`](../../lib/lux/current/README.md) - `Lux.current.locale`
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `Nav#locale` (URL prefix)
* [`../../lib/lux/type/README.md`](../../lib/lux/type/README.md) - `Lux::Type::LocaleType`, `Lux::Type::TranslatedType`
