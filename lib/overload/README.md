# lib/overload

Monkey-patches that reopen Ruby core/stdlib classes (`Object`, `String`,
`Array`, `Hash`, `Integer`, `Float`, `NilClass`, `Date`/`Time`,
`Dir`, `File`, ...) and add or override methods on them. These load
globally for the whole process - once required, every object in the app sees
them, including code outside Lux. They change core Ruby behavior, so read this
before assuming a stdlib method does what the docs say: several existing
methods are redefined here.

## Methods that differ from ActiveSupport / Sequel namesakes

* `String#constantize`, `classify`, `pluralize`, `singularize`, `camelize`, `underscore`, `tableize`, `humanize`, `demodulize`, `foreign_key`, `dasherize` come from Sequel's inflector (loaded after the overloads, so it wins).
* `String#parameterize(len = 50)` has no `separator:` and keeps `+`.
* `Array#wrap` is an instance HTML helper, not `Array.wrap`.
* `String#indent` also indents empty lines.
* `Object#try` and `blank?`/`present?` follow ActiveSupport semantics: anything answering `empty?` is blank when empty; `String#blank?` treats whitespace-only (Unicode too) as blank and undecodable bytes as content.

## Added methods, by class

### Object
See "Global helpers on Object" below - all of `Object`'s additions are callable on any value.

### String (`string.rb`)
* `constantize?` - `'User'.constantize?`; nil if undefined or not a constant name (`constantize` itself is Sequel's).
* `html_safe?` / `html_unsafe(script: false, style: false)` / `html_escape` - see [Output escaping](#output-escaping).
* `as_html` - tiny markdown: escaped text, newlines -> `<br />`, bare URLs -> links; returns markup.
* `trim(len)` - cut to `len` and append `...` (unchanged when it fits).
* `first(limit = 1)` / `last(num = 1)` - char slicing, ActiveSupport style.
* `wrap(node_name, opts={})` / `tag(node_name, **attrs, &block)` - wrap string in an HTML tag (via vendored html-tag).
* `parse_erb(scope = nil)` - render the string as ERB.
* `parameterize(len = 50)` - transliterate accents, slugify, cap `len` chars, no edge dashes.
* `qs_to_hash` - parse a query string into a Hash (keys and values unescaped).
* `db_safe` - strip everything but `[0-9a-zA-Z_]`.
* `colorize(color)` / `decolorize` - ANSI terminal color (palette in `ANSI_COLORS`).
* `escape` / `unescape` - percent-encoding valid in a path and a query (space -> `%20`, same as `Lux::Utils::Url.escape`); `unescape` also reads `+` as a space.
* `sha1` / `md5` - hex digests.
* `to_slug(len = 80)` - `parameterize` with `-` only.
* `remove_tags` - strip all `<...>` tags.
* `squish` - collapse whitespace and strip.
* `indent(amount = 2, char = ' ')` - prefix every line.

### Array (`array.rb`)
* `wrap(name, opts={})` - map each element through `#tag` (HTML).
* `last=` - set the last element.
* `to_sentence(words_connector:, two_words_connector:, last_word_connector:)` - Rails-like "a, b, and c"; always a String.
* `toggle(element)` - add/remove element, returns true when added.
* `all` - returns self (Sequel chaining).
* `xuniq` - `uniq` then keep only `present?`.
* `to_ul(klass=nil)` - render as `<ul><li>...`.

### Hash (`hash.rb`)
* `to_css` - sorted `k: v;` CSS string (values raw; tag builders escape the attribute).
* `deep_destroy(*keys)` / `deep_destroy!(*keys)` - recursively drop keys (string/symbol-insensitive) from nested Hash and Array-of-Hash; `!` replaces in place.
* `deep_stringify_keys` - recursively convert keys to strings (nested Hash + Array of Hash).
* `remove_empty(covert_to_s = false)` - drop keys/values that are blank.
* `tag(node_name, inner = nil, &block)` - render an HTML tag using self as attributes (via vendored html-tag).

### Integer (`integer.rb`)
* `pluralize(desc)` - "no users" / "1 user" / "5 users" (uses `String#pluralize` from Sequel's inflector extension, `Sequel.extension :inflector` in `lib/lux/loader.rb`).
* `dotted` - thousands grouping with `.` (e.g. `1234567` -> `1.234.567`).
* `to_filesize` - human file size (`B`/`KB`/`MB`/...).

### Float (`float.rb`)
* `as_currency(opts={})` - format as currency; opts `pretty`, `strip`, `symbol`.

### Numeric (`blank.rb`)
* `blank?` -> `false`.

### NilClass (`blank.rb`, `nil.rb`)
* `present?` -> `false`, `blank?` -> `true`. `nil.empty?` raises, as in plain Ruby.

### Symbol
No file in this directory patches Symbol directly.

### Date / Time / DateTime (`time.rb`)
* `Time.agop(secs)` - precise "18min 31sec" style duration.
* `Time.ago(start_time, end_time = nil)` - humanized relative time (via `Lux::Utils::TimeDifference`).
* `Time.monotonic` - `CLOCK_MONOTONIC` seconds.
* `Date#to_i` - epoch seconds (`to_time.to_i`; plain Ruby Date has no `to_i`).
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
* `Dir.require_all(folder, skip: nil)` - require every `.rb` under `folder`, shallowest files first then by path; skips `*_spec.rb`, `/app/views/`, `/app/assets/` and paths containing `skip`.

### Pathname (`pathname.rb`)
* `folders` / `files` - delegate to `Dir.folders` / `Dir.files`.
* `touch` - `FileUtils.touch`.
* `write_p(data)` - `File.write_p` (create parent dirs).

### File (`file.rb`)
* `File.write_p(file, data)` - write, creating parent dirs.
* `File.append(path, content)` - locked append.
* `File.delete?(path)` - delete if present, returns boolean.

### Thread::Simple (`thread_simple.rb`)
A small fixed-size worker-pool. `Thread::Simple.run { |t| t.add { ... } }`,
`Thread::Simple.each(list, size: 3) { |item| ... }`; named tasks readable via
`pool[name]` / `pool.named`. A raising task does not kill its worker; `run`/`stop` re-raise the first error after every worker is joined.

## Output escaping

Haml runs with `escape_html` + `use_html_safe`: every `=` escapes its value
unless the string answers `html_safe?`. Nothing is escaped on input or in Ruby.

* `String#html_safe?` - always false; a `Lux::SafeString` answers true.
* `String#html_unsafe(script: false, style: false)` - marks *trusted* markup as
  safe (`Lux::SafeString`, printed as is). It is not a sanitizer: only
  `<script>`/`<style>` tags are disabled; event-handler attributes,
  `javascript:` URLs and other tags pass through. Never call it on
  user-supplied HTML.
* `String#html_escape` - entity-escaped `Lux::SafeString`, for text glued into
  markup built by hand; on a `Lux::SafeString` it returns self.
* `Lux::SafeString.escape(value)` - value as markup: kept when `html_safe?`,
  escaped otherwise (the one rule `join`, `+` and tag builders share).
* `Lux::SafeString` (`lib/lux/utils/safe_string.rb`, required by `lib/lux/loader.rb` right after `string.rb`) - what rendered templates, cells and every tag builder
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

* `blank?` / `present?` - emptiness predicates, tuned per core class (`Array`/`Hash` -> `empty?`, `Numeric`/`Time`/`true` -> not blank, `false`/`nil` -> blank).
* `presence` - returns self if `present?`, else nil.
* `or(_or = nil, &block)` - returns `_or` (or block result) when self is blank or `0`.
* `try(method, *args)` - ActiveSupport semantics: nil when the receiver is nil or does not respond; a bare block yields self.
* `in?(collection)` - `collection.include?(self)`.
* `is_hash?` / `is_array?` / `is_numeric?` - type predicates (`is_hash?`/`is_array?` also accept classes whose name ends in `Hash`/`Array`, e.g. indifferent-access and JSONB wrappers).
* `is_true?` - true when `Lux::Utils::Boolean.parse` reads it as true (`true yes on t y 1`).
* `is!(value = :_nil)` - assert presence (no arg) or `is_a?`/ancestor membership (`5.is!(Numeric)`, `Foo.is!(Comparable)`), returning self or raising `ArgumentError`.
* `instance_variables_hash` - ivars (minus `@current` and `@_*`) as a Hash.

### Debug / raise helpers (NEVER commit)

These are interactive console helpers (`raise_variants.rb`), defined private on
`Object` so they work bare (`rr @user`) without answering `respond_to?`. They
must NEVER appear in library or committed code - if you find `r`/`rr`/`r?`/`m?`/`LOG`
in `lib/` or `plugins/`, delete it.

* `r(what)` - inspect-dump then `raise` (handy "print and halt").
* `rr(what)` - pretty console dump (amazing_print), no raise.
* `r?(object)` - dump an object's unique methods (instance, parent, module).
* `m?(object)` - list methods defined on the object/class minus its parent.
* `LOG(what)` - append to `./log/LOG.log` (and dump to screen on web requests).

## New top-level constants

* `Boolean` (`boolean.rb`) - alias for `Lux::Utils::Boolean`. Because `TrueClass`
  and `FalseClass` both `include` it, `value.is_a?(Boolean)` works as a boolean
  type check. Loading fails if another `Boolean` is already defined.
