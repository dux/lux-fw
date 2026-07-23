# lib/overload

Monkey-patches that reopen Ruby core/stdlib classes (`Object`, `String`,
`Array`, `Hash`, `Integer`, `Float`, `NilClass`, `Symbol`, `Date`/`Time`,
`Struct`, `Dir`, `File`, ...) and add or override methods on them. These load
globally for the whole process - once required, every object in the app sees
them, including code outside Lux. They change core Ruby behavior, so read this
before assuming a stdlib method does what the docs say: several existing
methods are redefined here.

## Overrides of existing core methods

These shadow methods that already exist in Ruby. Highest surprise potential.

* `String#first` - no-arg, returns the first char (`self[0,1]`), not Ruby 3.4's `first(n)`.
* `String#last(num = 1)` - returns last `num` chars (slices `self[len-num, len]`).
* `String#truncate` - alias of `#trim`; cuts to `len` chars and appends `&hellip;`.
* `String#html_safe(full = false)` - strips `<script>`/`<style>` tags; NOT Rails' "mark as safe".
* `Array#last=` - assigns the last element (`self[length-1] = what`).
* `Array#all` - returns `self` (a no-op for easier Sequel query chaining).
* `Array#wrap(name, opts={})` - maps each element through `el.tag(name, opts)` (HTML), not `Array.wrap`.
* `Array#without(*elements)` - alias of `#excluding`; `self - elements.flatten`.
* `Integer#pluralize(desc)` - returns a phrase like `"no users"` / `"1 user"` / `"5 users"` (relies on `String#pluralize` from an inflector loaded elsewhere).
* `Date#to_i` - `Time.parse(to_s).to_i` (epoch seconds), instead of Ruby's Julian day number.
* `TrueClass#to_i` -> `1`, `FalseClass#to_i` -> `0`.
* `NilClass#empty?` -> `true`, `NilClass#present?` -> `false`, `NilClass#blank?` -> `true`.
* `NilClass#is?(klass)` -> `false` (always).
* `Object#blank?` / `Object#present?` - global predicates added to every object (see below); core classes get tuned versions (`String#blank?` treats whitespace-only as blank, `Array#blank?`/`Hash#blank?` check length, `Numeric#blank?`/`Time#blank?` -> `false`, `FalseClass#blank?` -> `true`, `TrueClass#blank?` -> `false`).
* `Object.const_missing` - redefined for autoload: lazily scans `./app/**/*.rb`, maps file basename to CamelCase, and requires on first reference (thread-safe via a Monitor).

## Added methods, by class

### Object
See "Global helpers on Object" below - all of `Object`'s additions are callable on any value.

### String (`string.rb`)
* `constantize` / `constantize?` - `'User'.constantize`; `?` variant returns nil if undefined.
* `html_escape(display = false)` / `html_unsafe(full = false)` - storage-safe escaping (`#LT;` sentinel) and its inverse.
* `as_html` - tiny markdown: newlines -> `<br />`, bare URLs -> links.
* `trim(len)` (alias `truncate`) - cut to `len` and append `&hellip;`.
* `first` / `last(num = 1)` - char slicing (see overrides).
* `sanitize` / `quick_sanitize` - Sanitize.clean allowlist; quick variant strips inline styles except `text-align`.
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
* `to_csv` - list-of-lists -> `;`-joined, quoted CSV.
* `wrap(name, opts={})` - map each element through `#tag` (HTML).
* `last=` - set the last element.
* `to_sentence(opts={})` - Rails-like "a, b, and c".
* `toggle(element)` - add/remove element, returns true when added.
* `all` - returns self (Sequel chaining).
* `random_by_string(string)` - deterministic element pick from a string.
* `xuniq` - `uniq` then keep only `present?`.
* `to_ul(klass=nil)` - render as `<ul><li>...`.
* `shift_push` - rotate first element to the back, return it.
* `xmap` - like `map` but yields `(el, index)` and returns the original elements.
* `in_groups_of(num, fill = nil)` - slice into fixed-size groups (pad with `fill` unless `false`).
* `excluding(*elements)` (alias `without`) - set difference, flattened.

### Hash (`hash.rb`)
* `to_query(namespace=nil)` - build a sorted `?k=v&...` query string.
* `to_attributes` / `to_css` - sorted `k="v"` attribute string / `k: v;` CSS string.
* `deep_sort` - recursively sort by key.
* `deep_stringify_keys` / `deep_stringify_keys!` - recursively convert keys to strings (nested Hash + Array of Hash).
* `deep_symbolize_keys` / `deep_symbolize_keys!` - recursively convert keys to symbols (nested Hash + Array of Hash).
* `pluck(*args)` - select only the named keys (string-compared).
* `remove_empty(covert_to_s = false)` - drop keys/values that are blank.
* `to_js(opts = {})` - JSON with unquoted keys for embedding in JS.
* `deep_compact` (instance + `Hash.deep_compact(value)` class method) - recursively drop blank/`'0'` values.
* `reverse_merge` / `reverse_merge!` (aliases `with_defaults` / `with_defaults!`) - merge where self wins.
* `html_safe(key)` - run the value at `key` through `String#html_safe` in place.
* `tag(node_name, inner = nil, &block)` - render an HTML tag using self as attributes (via vendored html-tag).

### Integer (`integer.rb`)
* `pluralize(desc)` - "no users" / "1 user" / "5 users" (see overrides).
* `dotted` - thousands grouping with `.` (e.g. `1234567` -> `1.234.567`).
* `ordinalize` (alias `to_ordinal`) - `1` -> `1st`, `22` -> `22nd`.
* `to_filesize` - human file size (`B`/`KB`/`MB`/...).

### Float (`float.rb`)
* `as_currency(opts={})` - format as currency; opts `pretty`, `strip`, `symbol`.
* `format_with_underscores` - `_`-grouped 2-decimal string (nil if `<= 0`).
* `dotted(round_to=2)` - integer part dotted, comma + decimals.

### Numeric (`boolean.rb`, `blank.rb`)
* `to_b` - `self > 0`.
* `blank?` -> `false`.

### NilClass (`blank.rb`, `nil.rb`)
* `empty?` / `present?` / `blank?` - see overrides.
* `is?(klass)` -> `false`.

### Symbol
No file in this directory patches Symbol directly. (`Object#is_symbol?` reports symbol-ness.)

### Struct (`struct.rb`)
* `to_hash` - members zipped with values into a Hash.

### Date / Time / DateTime (`time.rb`)
* `Time.speed(num = 1) { ... }` - benchmark a block (1st run reported separately).
* `Time.agop(secs, desc = nil)` - precise "18min 31sec" style duration.
* `Time.ago(start_time, end_time = nil)` - humanized relative time (via `Lux::Utils::TimeDifference`).
* `Time.monotonic` - `CLOCK_MONOTONIC` seconds.
* `Time.for(value)` - coerce Numeric/String/responder into a Time (from Sinatra).
* `Date#to_i` - epoch seconds (see overrides).
* `Time` / `Date` / `DateTime` include `Lux::Utils::TimeOptions` -> `short` / `long` / `current` formatters.

### Hash / Array (`json.rb`)
Both include `Lux::Utils::Json` -> `to_jsons` (pretty in dev), `to_jsonp` (pretty), `to_jsonc` (compact, unquoted keys).

### Enumerable (`enumerable.rb`)
* `index_by` - `{ key_from_block => element }`.
* `index_with` - `{ element => value_from_block }`.
* `many?` - `count > 1`.

### Class (`class.rb`)
* `descendants(fast = false)` - all subclasses via ObjectSpace.
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
* `File.is_locked?(lock_file)` - flock probe with 0.1s timeout.

### Thread::Simple (`thread_simple.rb`)
A small fixed-size worker-pool. `Thread::Simple.run { |t| t.add { ... } }`,
`Thread::Simple.each(list, size: 3) { |item| ... }`; named tasks readable via
`pool[name]` / `pool.named`.

## Global helpers on Object

Added to `Object`, so callable on any value (`object.rb`, plus predicates in `blank.rb`):

* `blank?` / `present?` - emptiness predicates (tuned per core class, see overrides).
* `presence` - returns self if `present?`, else nil.
* `or(_or = nil, &block)` - returns `_or` (or block result) when self is blank or `0`.
* `try(*args, &block)` - nil-safe send; with a block, yields the (optionally sent) value.
* `andand(func=nil, &block)` - chain only if `present?`, else nil / empty hash.
* `in?(collection)` (alias `inside?`) - `collection.include?(self)`.
* `is_hash?` / `is_array?` / `is_string?` / `is_symbol?` / `is_numeric?` / `is_boolean?` - type predicates (`is_hash?`/`is_array?` match by class-name substring so they also catch indifferent-access variants).
* `is_true?` - true if `to_s` is `'true'`/`'on'`/`'1'`; `is_false?` is its negation.
* `is!(value = :_nil)` - assert presence (no arg) or type/ancestor membership, returning self or raising `ArgumentError`.
* `is?(value = nil)` - boolean form of `is!` (rescues the raise).
* `is_a!(klass, error = nil)` - true if `klass` is an ancestor; raises (or returns false) otherwise.
* `die(desc=nil, exp_object=nil)` - print red message + caller, then raise.
* `instance_variables_hash` - ivars (minus `@current` and `@_*`) as a Hash.

### Debug / raise helpers (NEVER commit)

These are interactive console helpers (`raise_variants.rb`, `object.rb`). They
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
  type check. Companions: `Object#to_b` (parses strings via `Boolean.parse`),
  `Numeric#to_b` (`self > 0`).
