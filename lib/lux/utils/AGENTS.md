# Lux::Utils - agent guide

Bag of single-file utility modules. Pure helpers, no request state.

## Canonical example

```ruby
# Lux.crypt is the public shim for Lux::Utils::Crypt
Lux.crypt.sha1('x')                     # secret-mixed hex digest
Lux.crypt.uid(12)                       # random 12-char id
Lux.crypt.encrypt(data, ttl: 1.hour)    # JWT
Lux.crypt.decrypt(token)                # raises on bad/expired; unsafe: true returns nil

# Per-request, IP-bound variant (DIFFERENT layer):
Lux.current.encrypt(data)               # password defaults to self.ip, ttl: 10.minutes
Lux.current.decrypt(token)              # password defaults to self.ip

# Other members - reach via full namespace
Lux::Utils::StringBase.encode(12345)
Lux::Utils::TimeDifference.new(t).humanize
Lux::Utils::Boolean.parse('yes')        # true / false / nil

# Monkey-patches loaded via lib/overload/{boolean,json,time}.rb
true.to_i               # 1     (Boolean)
{a:1}.to_jsonp          # ...   (Json)
Time.now.short          # ...   (TimeOptions)
12345.string_id         # ...   (StringBase via Integer reopen)
```

## Rules

* **`Lux.crypt` is global; `Lux.current.encrypt` is request-scoped.**
  Use `Lux.crypt` for tokens that any user should be able to verify
  (mail confirmation links, share URLs, internal job payloads). Use
  `Lux.current.encrypt` for short-lived tokens tied to the same session
  (CSRF-style guards, "logout this session" links, encrypted form
  hidden fields).
* **`Lux::Utils::Crypt.sha1` mixes in `Lux.config.secret`.** Hashes from
  two different apps don't match - this is intentional (HMAC-style),
  not a bug. For portable hashes use `Digest::SHA1.hexdigest` directly.
* **`Lux::Utils::Boolean.parse` returns nil for unknown input,** not
  false. Distinguish "false" from "missing" explicitly:
  `parsed = Lux::Utils::Boolean.parse(x); next if parsed.nil?`
* **Don't add unrelated helpers to this namespace.** `Lux::Utils` is for
  small, pure, single-file utilities. Anything with internal state,
  config, or callbacks belongs in its own subsystem under `lib/lux/<name>/`.
* **`Lux::Utils::Ref` and `Lux::Utils::PaginatedArray` live in the db
  plugin,** not here. Namespace is `Lux::Utils::*` but file location
  stays with the plugin because they're db-coupled.

## Don't

* Don't shadow with bare `Crypt`, `StringBase`, `TimeDifference`. These
  names previously polluted top level - they're explicitly namespaced
  now and downstream apps were migrated.
* Don't bypass `Lux.crypt` to reach `Lux::Utils::Crypt` directly in
  application code. The shim is the public API; the constant is the
  implementation.
* Don't put `Lux::Utils` constants under `module Lux` and rely on
  constant lookup to find `Utils::Foo` - always use the fully-qualified
  `Lux::Utils::Foo`. Otherwise a future rename of the parent module
  breaks silently.
* Don't add `extend self` to a util class. Crypt uses it (module +
  module-level methods). StringBase / TimeDifference / PaginatedArray
  are real classes with instances - keep that distinction.

## See also

* [`README.md`](./README.md) - human-facing reference with member-by-member examples
* [`../current/AGENTS.md`](../current/AGENTS.md) - `Lux.current.encrypt/decrypt`
