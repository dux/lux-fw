# Lux::Locale - agent guide

Namespaced translation lookup, flat text files on disk. **Every key must
be namespaced** (`'users.welcome'`, not `'welcome'`) - the first segment
selects the file `./config/locales/<namespace>.<locale>.txt`.

## Canonical example

```ruby
# --- boot ---
Lux.locale.default   = :en
Lux.locale.available = %i[en de hr]

# --- lookup ---
Lux.locale.t('users.welcome', name: 'Joe')            # 'Hi Joe'
Lux.locale.t('users.welcome', name: 'Joe', locale: :de)
Lux.locale.t('users.missing', fallback: 'Hi there')
Lux.locale.t('users.unknown')                         # '[users.unknown]'

# --- write (sorted, atomic) ---
Lux.locale.set('users.farewell', 'Bye %{name}', locale: :en)

# --- dynamic namespace: non-nil wins, nil falls through to file ---
Lux.locale.namespace(:product) do |subkey, locale|
  Product[subkey.split('.').last]&.translate(locale)
end

# --- global hooks ---
Lux.locale.before_get { |locale, key| Metrics.incr(key); nil }
Lux.locale.before_set { |locale, key, v| v.to_s.strip }

# --- template helper (auto-exposed) ---
# = t('users.welcome', name: @user.name)
```

File at `./config/locales/users.en.txt`:

```
farewell: Bye %{name}
welcome: Hi %{name}
```

## Rules

* **Namespace is mandatory.** Single-segment keys raise `ArgumentError`.
  Namespace = first dotted segment; everything after is the storage key.
* **Files are flat.** No YAML nesting. One `key: value` per line, sorted
  alphabetically on every `set`. Keys never contain spaces or colons.
* **Lookup chain**: `before_get` -> namespace handler -> `store` -> file
  -> same in default locale -> `fallback:` arg -> `"[full.key]"`. The
  bracket form is a visible-but-non-fatal marker, not an error.
* **`store` swaps the backend.** Any object with `.get(locale, ns, subkey)`
  and `.set(locale, ns, subkey, value)` is a valid store. When set, writes
  go through it and reads hit it before the flat file. The plugin auto-wires
  `LuxTranslation` (PG-backed) when `ApplicationModel` is defined.
* **Hooks short-circuit on non-nil.** `before_get` returning non-nil
  wins; nil falls through. `before_set` returning non-nil replaces the
  value being stored; nil leaves it untouched.
* **Current locale comes from `Lux.current.locale`** (typically set by
  `Nav` from the URL prefix). `Lux.locale.current` validates it against
  `available`; unknown -> `Lux::Locale::Unknown`.
* **Dev cache invalidates on mtime.** No reloader hook needed; just edit
  the file.
* **Interpolation uses `%{name}`** (Ruby's `String#%` with a hash).

## Don't

* Don't call `t('hi')` (no namespace) - it raises. Group keys by file.
* Don't reach into `./config/locales/*.txt` directly from app code.
  `Lux.locale.set` is the only safe writer (sorts, atomically renames,
  invalidates cache).
* Don't use `before_get` for logging only - return `nil` so the real
  lookup still runs. Returning a string short-circuits.
* Don't bypass `t()` and read files yourself for "one quick lookup" -
  you lose the fallback chain, interpolation, and the cache.
* Don't store locale-specific data that isn't a translation (URLs,
  feature flags) here - use `Lux.config`.

## See also

* [`README.md`](./README.md) - human reference
* [`../../lib/lux/current/AGENTS.md`](../../lib/lux/current/AGENTS.md) - `Lux.current.locale`
* [`../../lib/lux/application/AGENTS.md`](../../lib/lux/application/AGENTS.md) - `Nav#locale`
* [`../../lib/lux/type/AGENTS.md`](../../lib/lux/type/AGENTS.md) - `Lux::Type::LocaleType`
