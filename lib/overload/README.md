# lib/overload

Monkey-patches that reopen Ruby core/stdlib classes (`Object`, `String`,
`Array`, `Hash`, `Integer`, `Float`, `NilClass`, `Symbol`, `Date`/`Time`,
`Dir`, `File`, ...) and add or override methods on them. These load
globally for the whole process - once required, every object in the app sees
them, including code outside Lux. They change core Ruby behavior, so read this
before assuming a stdlib method does what the docs say: several existing
methods are redefined here.

## Overrides of existing core methods

These shadow methods that already exist in Ruby. Highest surprise potential.

* `String#last(num = 1)` - returns last `num` chars (the whole string when `num` exceeds its length), ActiveSupport style.
* `Array#last=` - assigns the last element (`self[length-1] = what`).
* `Array#all` - returns `self` (a no-op for easier Sequel query chaining).
* `Array#wrap(name, opts={})` - maps each element through `el.tag(name, opts)` (HTML), not `Array.wrap`.
* `Integer#pluralize(desc)` - returns a phrase like `"no users"` / `"1 user"` / `"5 users"` (relies on `String#pluralize` from an inflector loaded elsewhere).
* `Date#to_i` - `Time.parse(to_s).to_i` (epoch seconds), instead of Ruby's Julian day number.
* `NilClass#present?` -> `false`, `NilClass#blank?` -> `true`.
* `NilClass#is?(klass)` -> `false` (always).
* `Object#blank?` / `Object#present?` - global predicates added to every object (see below), ActiveSupport semantics: anything answering `empty?` is blank when empty; core classes get tuned versions (`String#blank?` treats whitespace-only as blank, `Array#blank?`/`Hash#blank?` check length, `Numeric#blank?`/`Time#blank?` -> `false`, `FalseClass#blank?` -> `true`, `TrueClass#blank?` -> `false`).

## Added methods, by class

### Object
See "Global helpers on Object" below - all of `Object`'s additions are callable on any value.

### String (`string.rb`)
* `constantize` / `constantize?` - `'User'.constantize`; `?` variant returns nil if undefined.
* `html_safe?` / `html_unsafe(script: false, style: false)` / `html_escape` - see [Output escaping](#output-escaping).
* `as_html` - tiny markdown: escaped text, newlines -> `<br />`, bare URLs -> links; returns markup.
* `trim(len)` - cut to `len` and append `...`.
* `first(limit = 1)` / `last(num = 1)` - char slicing, ActiveSupport style.
* `wrap(node_name, opts={})` / `tag(node_name, **attrs, &block)` - wrap string in an HTML tag (via vendored html-tag).
* `fix_ut8` - re-encode to UTF-8 replacing invalid bytes.
* `parse_erb(scope = nil)` - render the string as ERB.
* `parameterize` (alias `to_url`) - transliterate accents, slugify, cap 50 chars.
* `qs_to_hash` - parse a query string into a Hash.
* `attribute_safe` / `db_safe` - strip quotes / non-`[0-9a-zA-Z_]`.
* `span_green` / `span_red` - wrap in a colored `<span>`.
* `colorize(color)` / `decolorize` - ANSI terminal color (palette in `ANSI_COLORS`).
* `escape` / `unescape` - CGI escape (escape forces `%20` for spaces).
* `sha1` / `md5` - hex digests.
* `extract_scripts!(list: false)` - destructively pull `<script>` blocks out.
* `to_slug(len = 80)` - lowercase, `_`/`-` separated slug.
* `remove_tags` - strip all `<...>` tags.
* `squish` - collapse whitespace and strip.
* `indent(amount = 2, char = ' ')` - prefix every line.

### Array (`array.rb`)
* `wrap(name, opts={})` - map each element through `#tag` (HTML).
* `last=` - set the last element.
* `to_sentence(opts={})` - Rails-like "a, b, and c" (does not change the array).
* `toggle(element)` - add/remove element, returns true when added.
* `all` - returns self (Sequel chaining).
* `xuniq` - `uniq` then keep only `present?`.
* `to_ul(klass=nil)` - render as `<ul><li>...`.

### Hash (`hash.rb`)
* `to_css` - sorted `k: v;` CSS string.
* `deep_stringify_keys` - recursively convert keys to strings (nested Hash + Array of Hash).
* `remove_empty(covert_to_s = false)` - drop keys/values that are blank.
* `tag(node_name, inner = nil, &block)` - render an HTML tag using self as attributes (via vendored html-tag).

### Integer (`integer.rb`)
* `pluralize(desc)` - "no users" / "1 user" / "5 users" (see overrides).
* `dotted` - thousands grouping with `.` (e.g. `1234567` -> `1.234.567`).
* `to_filesize` - human file size (`B`/`KB`/`MB`/...).

### Float (`float.rb`)
* `as_currency(opts={})` - format as currency; opts `pretty`, `strip`, `symbol`.
* `dotted(round_to=2)` - integer part dotted, comma + decimals.

### Numeric (`blank.rb`)
* `blank?` -> `false`.

### NilClass (`blank.rb`, `nil.rb`)
* `present?` / `blank?` - see overrides. `nil.empty?` raises, as in plain Ruby.
* `is?(klass)` -> `false`.

### Symbol
No file in this directory patches Symbol directly.

### Date / Time / DateTime (`time.rb`)
* `Time.speed(num = 1) { ... }` - benchmark a block (1st run reported separately).
* `Time.agop(secs, desc = nil)` - precise "18min 31sec" style duration.
* `Time.ago(start_time, end_time = nil)` - humanized relative time (via `Lux::Utils::TimeDifference`).
* `Time.monotonic` - `CLOCK_MONOTONIC` seconds.
* `Date#to_i` - epoch seconds (see overrides).
* `Time` / `Date` / `DateTime` include `Lux::Utils::TimeOptions` -> `short` / `long` / `current` formatters.

### Hash / Array (`json.rb`)
Both include `Lux::Utils::Json` -> `to_jsons` (pretty in dev), `to_jsonp` (pretty), `to_jsonc` (compact, unquoted keys).

### Enumerable (`enumerable.rb`)
* `index_by` - `{ key_from_block => element }`.
* `many?` - `count > 1`.

### Class (`class.rb`)
* `descendants` - all subclasses, walked through `Class#subclasses`.
* `source_location(as_folder=false)` - file (or dir) defining the class, relative to `Lux.root`.

### Dir (`dir.rb`)
* `Dir.folders(dir)` / `Dir.files(dir, opts={})` - sorted child folders / files (`ext: false` strips extensions).
* `Dir.find(dir_path, opts={})` - deep file search (`ext`, `root`, `hash`, `invert`, `shallow`, `join`; `'./app#assets'` shorthand sets root); accepts a block.
* `Dir.require_all(folder, opts={})` - require every `.rb` (skips specs and `/app/views/`).
* `Dir.mkdir?(name)` - `FileUtils.mkdir_p`.

### Pathname (`dir.rb`, `pathname.rb`)
* `folders` / `files` - delegate to `Dir.folders` / `Dir.files`.
* `touch` - `FileUtils.touch`.
* `write_p(data)` - `File.write_p` (create parent dirs).

### File (`file.rb`)
* `File.write_p(file, data)` - write, creating parent dirs.
* `File.append(path, content)` - locked append.
* `File.ext(name)` - 3- or 4-char extension, else nil.
* `File.delete?(path)` - delete if present, returns boolean.

### Thread::Simple (`thread_simple.rb`)
A small fixed-size worker-pool. `Thread::Simple.run { |t| t.add { ... } }`,
`Thread::Simple.each(list, size: 3) { |item| ... }`; named tasks readable via
`pool[name]` / `pool.named`.

## Output escaping

Haml runs with `escape_html` + `use_html_safe`: every `=` escapes its value
unless the string answers `html_safe?`. Nothing is escaped on input or in Ruby.

* `String#html_safe?` - always false; a `Lux::SafeString` answers true.
* `String#html_unsafe(script: false, style: false)` - returns the string as a
  `Lux::SafeString` (printed as is). `<script>` / `<style>` are neutralized
  unless allowed.
* `String#html_escape` - entity-escaped `Lux::SafeString`, for text glued into
  markup built by hand.
* `Lux::SafeString` - what rendered templates, cells and every tag builder
  (`'x'.tag(:b)`, `{}.tag`, `HtmlTag.div`) return. `safe + text` escapes the text
  and stays safe; `Lux::SafeString.join(parts)` does the same for a list. Any
  other String method (`gsub`, interpolation) returns a plain String, which `=`
  escapes again - so build markup with `tag`, not with `%[<b>#{x}</b>]`.
* Tag builders escape plain inner text and block results; `n.push` inserts raw.
* Haml's buffer is a `Lux::SafeString::Buffer`, so template output handed back by
  a block (`- t.col do`, `= box do` with dynamic lines) is markup. Static-only
  blocks compile to a plain literal: a helper taking a block should still wrap
  it with `capture { yield }` (`Lux::Template::Helper#capture`).
* `!=` in Haml prints raw; `&=` always escapes.

## Global helpers on Object

Added to `Object`, so callable on any value (`object.rb`, plus predicates in `blank.rb`):

* `blank?` / `present?` - emptiness predicates (tuned per core class, see overrides).
* `presence` - returns self if `present?`, else nil.
* `or(_or = nil, &block)` - returns `_or` (or block result) when self is blank or `0`.
* `try(method, *args)` - ActiveSupport semantics: nil when the receiver is nil or does not respond; a bare block yields self.
* `in?(collection)` - `collection.include?(self)`.
* `is_hash?` / `is_array?` / `is_numeric?` - type predicates (`is_hash?`/`is_array?` match by class-name substring so they also catch indifferent-access variants).
* `is_true?` - true when `Lux::Utils::Boolean.parse` reads it as true (`true yes on t y 1`).
* `is!(value = :_nil)` - assert presence (no arg) or type/ancestor membership, returning self or raising `ArgumentError`.
* `is?(value = nil)` - boolean form of `is!` (rescues the raise).
* `is_a!(klass, error = nil)` - true if `klass` is an ancestor; raises (or returns false) otherwise.
* `die(desc=nil, exp_object=nil)` - private; print red message + caller, then raise.
* `instance_variables_hash` - ivars (minus `@current` and `@_*`) as a Hash.

### Debug / raise helpers (NEVER commit)

These are interactive console helpers (`raise_variants.rb`), defined private on
`Object` so they work bare (`rr @user`) without answering `respond_to?`. They
must NEVER appear in library or committed code - if you find `r`/`rr`/`r?`/`m?`/`LOG`
in `lib/` or `plugins/`, delete it.

* `r(what)` - inspect-dump then `raise` (handy "print and halt").
* `rr(what)` - pretty console dump (awesome_print), no raise.
* `r?(object)` - dump an object's unique methods (instance, parent, module).
* `m?(object)` - list methods defined on the object/class minus its parent.
* `LOG(what)` - append to `./log/LOG.log` (and dump to screen on web requests).
* `ap` - a `puts` fallback is defined if awesome_print is absent.

## New top-level constants

* `Boolean` (`boolean.rb`) - alias for `Lux::Utils::Boolean`. Because `TrueClass`
  and `FalseClass` both `include` it, `value.is_a?(Boolean)` works as a boolean
  type check. Loading fails if another `Boolean` is already defined.
