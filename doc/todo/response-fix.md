# Response, Cache, Cookie, and Session Cleanup Plan

## Goals

Make Lux response handling more consistent, explicit, and professional while keeping the common path short and sane.

Primary goals:

* Keep private cache as the default. Do not add `response.cache_private`.
* Make public cache an explicit opt-in.
* Ensure public cache never emits cookies.
* Centralize response cache decisions in one policy object.
* Add `Lux::UNSET` and use it where `nil` or `false` are valid explicit values.
* Keep existing public APIs working where practical, but move documentation toward the cleaner API.

## Desired API

Default behavior should require no call:

```ruby
# default
# Cache-Control: private, must-revalidate, max-age=0
```

Explicit public cache:

```ruby
response.cache.public = true
response.cache.max_age = 10.minutes
response.cache.stale_while_revalidate = 1.hour
```

Optional shortcut for the common public-cache case:

```ruby
response.cache_public 10.minutes
```

ETags:

```ruby
response.etag :users, User.max(:updated_at)
response.cache.etag :users, User.max(:updated_at)
```

No-store:

```ruby
response.no_store
response.cache.no_store = true
```

Do not add:

```ruby
response.cache_private
```

Private cache is the default and should not need a shortcut.

## Add `Lux::UNSET`

Define one framework-wide sentinel early in boot, likely in `lib/lux/lux.rb` or another always-loaded core file:

```ruby
module Lux
  UNSET ||= Object.new.freeze
end
```

Use it only when method argument absence must be different from an explicit `nil` or `false`.

Always compare with identity:

```ruby
value.equal?(Lux::UNSET)
```

Do not compare with `==`.

Optional nicer inspect output:

```ruby
module Lux
  UNSET ||= Object.new.tap do |obj|
    def obj.inspect = 'Lux::UNSET'
    def obj.to_s = inspect
  end.freeze
end
```

Use simple `Object.new.freeze` unless debug output is worth the extra code.

## Audit for `Lux::UNSET` usage

Search for optional argument patterns that cannot distinguish missing from falsey values:

```ruby
def foo value = nil
  return @foo unless value
end
```

Replace where appropriate:

```ruby
def foo value = Lux::UNSET
  return @foo if value.equal?(Lux::UNSET)

  @foo = value
end
```

Likely files and methods to inspect first:

* `lib/lux/response/response.rb`
  * `body`
  * `content_type`
  * `status`
  * `early_hints`
  * any setter/getter combined methods
* `lib/lux/controller/controller.rb`
  * `layout`
  * render option normalization
* `lib/lux/config/config.rb`
  * setter/getter style config helpers
* `lib/lux/cache/cache.rb`
  * APIs that may intentionally cache `nil` or `false`
* `lib/lux/current/current.rb`
  * helpers that accept optional arguments
* `lib/lux/current/lib/session.rb`
  * methods where `nil` means deletion or an explicit stored value
* `lib/lux/response/lib/header.rb`
  * header get/set helpers

Do not blindly convert everything. Use `Lux::UNSET` only where it improves correctness.

## Introduce `Lux::Response::CachePolicy`

Add a small cache policy object owned by `Lux::Response`:

```ruby
response.cache
```

Suggested responsibilities:

* Track whether the response is public or private.
* Track `max_age`.
* Track `stale_while_revalidate`.
* Track `no_store`.
* Generate `Cache-Control`.
* Decide whether cookies may be emitted.
* Support ETag helpers or delegate to response.

Suggested shape:

```ruby
module Lux
  class Response
    class CachePolicy
      attr_accessor :max_age, :stale_while_revalidate

      def initialize response
        @response = response
        @public = false
        @no_store = false
        @max_age = 0
      end

      def public= value
        @public = !!value
      end

      def public?
        @public
      end

      def private?
        !public?
      end

      def no_store= value
        @no_store = !!value
      end

      def no_store?
        @no_store
      end

      def cached?
        @max_age.to_i > 0
      end

      def allow_cookies?
        private? && !no_store?
      end

      def header_value
        return 'no-store' if no_store?

        parts = []
        parts << (public? ? 'public' : 'private, must-revalidate')
        parts << 'max-age=%d' % @max_age.to_i
        parts << 'stale-while-revalidate=%d' % @stale_while_revalidate.to_i if @stale_while_revalidate
        parts.join(', ')
      end
    end
  end
end
```

Initialize it in `Lux::Response#initialize`:

```ruby
def initialize
  @render_start = Time.monotonic
  @headers = Lux::Response::Header.new
  @cache = Lux::Response::CachePolicy.new(self)
end
```

Keep compatibility methods:

```ruby
def max_age
  cache.max_age
end

def max_age= age
  cache.max_age = age.to_i
  cache.public = true if age.to_i > 0
end

def cached?
  cache.cached?
end

def public?
  cache.public?
end

def public= value
  cache.public = value
end
```

Note: docs currently mention `response.public = true`, but current code does not implement it. Either implement it as compatibility or remove it from docs. Prefer implementing it as compatibility and documenting `response.cache.public = true` as the primary API.

## Cache and cookie rules

Make these rules explicit and centralized:

* Private cache is default.
* Public cache is opt-in.
* Public cache never emits `Set-Cookie`.
* Public cache should not persist flash.
* Flash forces private cache and `max-age=0`.
* `no-store` never emits cookies unless there is a clear reason to override this later.
* Manual `Cache-Control` headers should not accidentally bypass cookie safety.

Current risky behavior:

```ruby
response.headers['cache-control'] = 'public, max-age=60'
```

This can be public at the header level while `response.max_age` still equals `0`, causing session cookies to be emitted.

Possible policy:

* Prefer setting cache through `response.cache`.
* If user manually sets `cache-control`, parse enough to know if it contains `public` or `no-store` before deciding on cookies.
* Or, better, discourage manual cache-control mutations and document `response.cache` as the supported API.

## Response body cleanup

Update `Lux::Response#body` to use `Lux::UNSET`:

Current issue:

```ruby
response.body ''
response.body false
response.body nil
```

These are ambiguous because the method uses truthiness to decide whether body data was passed.

Desired behavior:

```ruby
def body data = Lux::UNSET, opts = {}
  if block_given?
    opts = data.equal?(Lux::UNSET) ? {} : data
    @body = yield @body
    return @body
  end

  return @body if data.equal?(Lux::UNSET)

  opts ||= {}
  opts.is!(Hash).each { |k, v| public_send k, *v }
  @body = data unless @body
end
```

Decide whether `body(nil)` should set a nil body or clear the body. Be explicit and test it.

Recommendation:

* `response.body` gets the body.
* `response.body nil` explicitly sets body to nil.
* Add `response.clear_body` if clearing is needed.

Also avoid serializing hashes too early in `body`. Let finalization serialize the raw body once so content type remains correct.

## Content type cleanup

Current `content_type` uses `@content_type ||= type`, so later explicit calls do not override earlier implicit values.

Recommended behavior:

* Getter with no argument.
* Setter always sets.
* Use `Lux::UNSET` if method remains combined get/set.

Example:

```ruby
def content_type in_type = Lux::UNSET
  return @content_type if in_type.equal?(Lux::UNSET)

  @content_type = normalize_content_type(in_type)
end

alias content_type= content_type
```

Ensure aliases still work with Ruby setter syntax.

## Status cleanup

Current `status` combined getter/setter mostly works, but `nil` cannot be set intentionally and the method uses truthiness.

Recommended:

```ruby
def status num = Lux::UNSET
  return @status if num.equal?(Lux::UNSET)

  ...validate...
  @status = num
end

alias status= status
```

## 204 and 304 response semantics

Current no-body behavior sets a body string:

```ruby
@status = 204
@body = 'Lux HTTP ERROR 204: NO CONTENT'
```

Change this.

Expected:

* 204 response has empty body.
* 304 response has empty body.
* 304 should not need a content type.
* `Content-Length` should be correct for the final body.

Suggested:

```ruby
if [204, 304].include?(@status.to_i)
  @body = ''
end
```

Then decide whether to omit `content-type` and/or `content-length` for these statuses.

## ETag cleanup

Current ETag behavior is useful but should be aligned with cache policy:

* Strong ETag for public cache.
* Weak ETag for private/non-public cache is acceptable.
* Do not set 304 body text.
* Respect `current.no_cache?`.
* Ensure ETag is based on final body when auto-generated.
* Keep explicit `etag(*args)` support.

Potential API:

```ruby
response.etag :users, User.max(:updated_at)
response.cache.etag :users, User.max(:updated_at)
```

Implementation can keep the real method on `Response` and let `CachePolicy#etag` delegate.

## Session cleanup

Current session security check updates `_c` timestamp on every request, which often changes the encrypted session cookie every private request.

Add dirty tracking:

```ruby
session.dirty?
session.changed?
session.touch!
```

Track original serialized session after initialization:

```ruby
@original_hash = Marshal.load(Marshal.dump(@hash))
```

or store original JSON after security initialization.

Cookie generation should return nil unless the session actually changed or must be refreshed.

Potential policy:

* Writes to session mark dirty.
* Deletes mark dirty only if key existed.
* Security timestamp refresh happens only periodically, not every request.
* Flash writes mark session dirty only when flash is non-empty or changed.

## Cookie cleanup

Move cookie string creation to a small helper or use Rack helpers.

Issues to inspect:

* Manual cookie construction.
* Domain is always added, which may be bad for localhost/IP hosts.
* `secure` casing should be consistent (`Secure`).
* Multiple `Set-Cookie` values are not well represented by a single string.
* Need support for future cookie additions beyond session.

Recommended session cookie defaults:

```ruby
httponly: true
same_site: :lax
secure: request.ssl?
path: '/'
domain: configured domain or valid nav domain only
max_age: Lux.config.session_cookie_max_age
```

Add config options if needed:

```ruby
Lux.config.session_cookie_same_site
Lux.config.session_cookie_secure
Lux.config.session_cookie_domain
```

## Flash cleanup

Current flash is stored under `current.session[:lux_flash]` during response finalization.

Rules:

* Flash present forces private cache.
* Flash present forces `max-age=0`.
* Flash should never be persisted on public cache.
* Flash behavior should be tested around redirects and after callbacks.

Consider making flash persistence explicit:

```ruby
write_flash_to_session
```

called before cookie generation.

## Header helper cleanup

Current `Response#header` likely has a bug:

```ruby
if args.first.class == Hash
  args.each{|k,v| header k, v.to_s if k && v }
end
```

`args` is an array, so this should probably be:

```ruby
args.first.each { |k, v| header k, v if k && v }
```

Also consider whether setting a header to `nil` should delete it.

Potential API:

```ruby
response.header 'x-test'              # get
response.header 'x-test', 'value'     # set
response.header 'x-test', nil         # delete? decide
response.headers['x-test'] = 'value'  # raw access
response.headers.delete 'x-test'
```

Use `Lux::UNSET` here if `nil` is a valid value or if delete semantics are needed.

## Early hints cleanup

Current duplicate check compares the stored array against `link`:

```ruby
@early_hints.push [link, type] if type && !@early_hints.include?(link)
```

Should likely be:

```ruby
hint = [link, type]
@early_hints.push hint if type && !@early_hints.include?(hint)
```

Also inspect whether early hints are actually emitted anywhere.

## Redirect cleanup

Current redirect body is useful for browser fallback, but review:

* Keep HTML fallback body.
* Keep `Location` header.
* Keep `throw :done` behavior unless replacing with a clearer halt mechanism.
* Ensure status is 3xx.
* Ensure redirect flash forces private cache and session cookie.
* Consider using `response.halt` semantics internally for consistency later.

## File response cleanup

`Lux::Response::File` sets its own ETag and content headers.

Review:

* ETag compare currently checks raw `key`, while response header includes quotes.
* 304 from file should have empty body.
* Static files should probably use public cache by default when served from public assets.
* Do not emit session cookies for static files.

## Tests to add

Add focused response specs. Suggested test groups:

### Defaults

* Default response is private.
* Default response has `Cache-Control: private, must-revalidate, max-age=0`.
* Default private response may emit session cookie if session changed.

### Public cache

* `response.cache.public = true` emits public cache-control.
* `response.cache_public 60` emits public cache-control and max-age.
* Public response does not emit `Set-Cookie` after session read.
* Public response does not emit `Set-Cookie` after session write, or raises/ignores according to chosen policy.
* Public response with flash is forced private or rejects flash according to chosen policy.

### No-store

* `response.no_store` emits `Cache-Control: no-store`.
* No-store does not emit cookies unless explicitly allowed.

### Body and UNSET

* `response.body` reads current body.
* `response.body ''` sets empty string body.
* `response.body false` sets false body and finalizes predictably.
* `response.body nil` behavior is explicit and tested.
* Hash body serializes once to JSON.

### Status/content type

* `response.status nil` behavior is explicit.
* Invalid status falls back or raises according to current behavior.
* Later explicit `content_type` overrides earlier implicit type.

### 204/304/HEAD

* 204 has empty body.
* 304 has empty body.
* HEAD preserves content-length for GET-equivalent body and sends empty body.

### ETag

* Matching ETag returns 304.
* 304 body is empty.
* `Cache-Control: no-cache` with `current.can_clear_cache` bypasses ETag.
* Auto ETag is based on final body after app `after` callback.

### Session

* Reading session without changes does not rewrite cookie after initial stabilization.
* Writing session emits cookie on private response.
* Public cache suppresses session cookie.
* Session delete marks dirty only when key existed.

### Cookies

* Cookie has `HttpOnly`.
* Cookie has `SameSite=Lax` by default.
* Cookie has `Secure` on HTTPS.
* Cookie omits invalid domain for localhost/IP.

## Documentation updates

Update:

* `README.md`
* `lib/lux/response/README.md`

Replace old examples:

```ruby
response.max_age = 10
response.public = true
```

with preferred examples:

```ruby
response.cache.public = true
response.cache.max_age = 10
```

and shortcut:

```ruby
response.cache_public 10
```

Document clearly:

* Private is default.
* Public cache is opt-in.
* Public cache never sets cookies.
* Flash makes response private.
* Use `response.no_store` for sensitive pages.

## Migration and compatibility

Keep these existing APIs working initially:

```ruby
response.max_age = 10
response.public = true
response.public?
response.cached?
response.etag *args
```

Implementation note:

* `response.max_age = 10` should probably imply public cache for backward compatibility, because current behavior treats positive max-age as public.
* `response.public = true` should become a compatibility wrapper around `response.cache.public = true`.
* Existing manual `cache_control` controller helper can stay, but docs should prefer `response.cache`.

## Suggested implementation order

1. Add `Lux::UNSET`.
2. Convert `Response#body`, `Response#status`, and `Response#content_type` to `Lux::UNSET`.
3. Add tests for falsey body/status/content-type behavior.
4. Add `Response::CachePolicy` and `response.cache`.
5. Wire `write_response_header` through `response.cache`.
6. Add compatibility wrappers for `max_age`, `max_age=`, `public=`, `public?`, and `cached?`.
7. Make cookie emission depend on `response.cache.allow_cookies?`.
8. Fix 204 and 304 body semantics.
9. Fix header hash setting and early hints duplicate check.
10. Add session dirty tracking.
11. Improve cookie generation.
12. Review file responses and static file cache behavior.
13. Update docs.
14. Run the full spec suite.

## Open decisions

Decide before implementation:

* Should public cache plus session write raise, ignore cookie, or silently allow memory-only session change for current request?
* Should `response.body nil` mean set nil body or clear body?
* Should manual `Cache-Control` header be parsed for cookie safety?
* Should `no-store` suppress cookies always, or only suppress cache while still allowing session cookies?
* Should static files automatically set public cache even when `max_age` is not set?
* Should `response.max_age = 10` continue to imply public cache forever, or only during a compatibility window?
