# Lux::Locale

Small, namespaced translation lookup. Flat text files on disk, dotted
keys, two extension points for dynamic sources. No external i18n gem.

## Small example

```ruby
Lux.locale.default   = :en
Lux.locale.available = %i[en de]

Lux.locale.t('users.welcome', name: 'Joe')        # "Hi Joe"
Lux.locale.set('users.welcome', 'Hi %{name}', locale: :en)
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

## On-disk format

One flat text file per `(namespace, locale)` at
`./config/locales/<namespace>.<locale>.txt`. One entry per line,
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
3. `store.get(:users, :de, 'welcome')` if a store is configured.
4. File `./config/locales/users.de.txt`, line `welcome: ...`.
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
| `t(key, locale:, fallback:, **vars)` | string |
| `set(key, value, locale:)` | the stored value |
| `namespace(name) { \|subkey, locale\| ... }` | registers handler |
| `before_get { \|locale, key\| ... }` | registers hook |
| `before_set { \|locale, key, value\| ... }` | registers hook |
| `reload!` | drops the in-process file cache |

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

`current` reads `Lux.current.locale` (typically set by `Nav` from the URL
prefix). Falls back to `default`. Unknown locale -> `Lux::Locale::Unknown`.

## Notes

* The in-process file cache invalidates on file `mtime` change, so dev
  edits show up without restart or reloader wiring.
* `before_get` returning `nil` falls through to the normal chain. Same
  for `before_set` - returning `nil` leaves the value untouched.
* Single-segment keys (`'hi'`) raise `ArgumentError`. Namespace is
  mandatory so files split predictably.

## See also

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`../../lib/lux/current/README.md`](../../lib/lux/current/README.md) - `Lux.current.locale`
* [`../../lib/lux/application/README.md`](../../lib/lux/application/README.md) - `Nav#locale` (URL prefix)
* [`../../lib/lux/type/README.md`](../../lib/lux/type/README.md) - `Lux::Type::LocaleType`
