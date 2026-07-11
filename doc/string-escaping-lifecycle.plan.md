# String escaping lifecycle migration

Goal: move from escape-on-write (`#LT;` sentinel baked into DB data) to
store-raw / escape-on-output, with a single `String#unsafe` opt-out. Escape
only what is needed per output context: `<` for HTML text, `<` for JSON.

## Guiding rule

Data is stored RAW (real `<`). Escaping happens only at an output boundary
(haml `=` output, JSON exporter). `.unsafe` marks a string to skip HTML-text
escaping. Attribute escaping is a separate haml path and stays full-entity.

## Character policy (settled)

* HTML text output (`= value`): escape `<` -> `&lt;` only.
  - `>` not needed (no `<` before it = plain text).
  - `"` / `'` not needed (handled by haml attribute path, full escape).
  - `&` not escaped: entities in a text node decode to chars but do NOT
    re-enter the tokenizer, so `&lt;script&gt;` renders as visible text, never
    executes. Only cost is display fidelity.
* HTML attributes (`%a{href: value}`): unchanged - haml `attribute_builder`
  keeps full-entity escaping incl. quotes. We do NOT touch this path.
* JSON output: escape `<` -> `<`, `>` -> `>`, and U+2028 / U+2029 ->
  ` ` / ` `. Lossless: `JSON.parse` restores originals. Protects
  `</script>` breakout when JSON is inlined in a page.

## String lifecycle (target state)

1. Form submit (browser -> server)
   - Params arrive raw. NO mutation. (Today: `make_hash_html_safe` rewrites
     `<` -> `#LT;` here - remove it.)
2. API / params layer
   - `JSON.parse` / multipart parse -> keep raw.
3. DB entry
   - Store raw strings (real `<`). Single source of truth = raw.
   - SQL-injection safety stays where it is (parameterized queries / ORM),
     orthogonal to this work.
4. Read from DB
   - Raw strings returned verbatim.
5a. Render via haml
   - `= value`            -> escaped `<` -> `&lt;` (default).
   - `= value.unsafe`     -> raw, but `<script>` / `<style>` re-neutralized.
   - `= value.unsafe(script: true)` / `(style: true)` -> allow that tag.
   - `= value.unsafe(true)` -> allow both.
5b. Render via API (JSON)
   - JSON exporter escapes `<`,`>`,U+2028/9 to `\uXXXX`. `.unsafe` is a no-op
     in JSON (JSON is data; escaping is lossless).

## Mechanism (haml 7.1)

haml compiles `= v` to `::Haml::Util.escape_html_safe((v))` when built with
`use_html_safe: true`. `escape_html_safe` skips escaping when the value answers
`html_safe? == true`. Attributes call `Haml::Util.escape_html` directly (full).

So:
* Build templates with `escape_html: true, use_html_safe: true`.
* Override ONLY `Haml::Util.escape_html_safe` with the minimal `<`-only escape.
  Leave `Haml::Util.escape_html` (attributes) untouched.
* `.unsafe` returns a `Lux::Utils::SafeString` whose `html_safe?` is true.

Gotcha: `escape_html_safe` does `html = html.to_s` BEFORE the `html_safe?`
check, and `String#to_s` on a subclass returns a fresh plain String (dropping
the marker). `Lux::Utils::SafeString` must override `to_s` to return self (same trick
as `ActiveSupport::SafeBuffer`).

## New API

```ruby
str.unsafe               # raw HTML, <script>/<style> stay escaped
str.unsafe(script: true) # also allow <script>
str.unsafe(style: true)  # also allow <style>
str.unsafe(true)         # allow both

class Lux::Utils::SafeString < String
  def html_safe?; true; end
  def to_s; self; end
end
```

`.unsafe` builds a `Lux::Utils::SafeString` of the raw content with `<script`/`<style`
re-escaped to `&lt;script`/`&lt;style` unless that tag was explicitly allowed.

## Work items

### A. Core string layer  (`lib/overload/string.rb`)
* Remove `html_escape`, `html_unsafe`, `html_safe`, and the `#LT;` / `$LT;`
  sentinels.
* Add `Lux::Utils::SafeString` and `String#unsafe(all=false, script:, style:)`.
* Decide fate of `as_html` / `strip_tags` helpers (keep, unrelated).

### B. haml wiring
* `lib/lux/template/template.rb:148` - `escape_html: false`
  -> `escape_html: true, use_html_safe: true`.
* Add a small patch (e.g. `lib/lux/render/haml_escape.rb`) overriding
  `Haml::Util.escape_html_safe` to the `<`-only escaper that respects
  `html_safe?`. Load it in the boot/loader.
* Confirm Tilt passes `use_html_safe` through to `Haml::Engine`.

### C. Remove write-side mutation
* `lib/lux/api/base_class.rb:620-627` - delete `make_hash_html_safe` `#LT;`
  rewrite (or make it a no-op / rename).
* `lib/lux/api/base_instance.rb:41-42` - drop the `html_safe:` param call.

### D. JSON exporter
* Centralize JSON emission through one helper, e.g. `Lux.json(obj)` that runs
  `JSON.generate` then post-escapes `< > U+2028 U+2029` to `\uXXXX`.
* Route existing emitters through it:
  - `lib/lux/response/response.rb:160, 375`
  - `lib/lux/api/base_class.rb:29, 51`
  - `lib/lux/api/base_instance.rb:103-104`
  - `lib/lux/controller/params_dsl.rb:259`
  - `lib/lux/api/doc/*` (schemas) - optional, internal.
* Precedent already exists at `lib/lux/response/response.rb:264`.

### E. Update read-side callers
* `lib/overload/hash.rb:91-93` (`Hash#html_safe key`) - rework to `.unsafe`
  or drop.
* `lib/lux/view_cell/view_cell.rb:55` - `out.html_safe` -> `.unsafe` (cells
  emit trusted markup).
* `plugins/web_common/load/html/table/html_table_app.rb:198` - `.html_safe`
  -> `.unsafe`.
* JS mirror `plugins/web_common/mount/app/assets/auto/common/js/lib/app_helpers.js:134`
  (`$.htmlSafe`) - drop `#LT;` handling; align with new model.

### F. Template audit (the blast radius)
Flipping `escape_html` on makes EVERY existing `= foo` escape. Any `=` that
intentionally emits HTML must be tagged `.unsafe`.
* `rg -n "^\s*[=&]=?\s" app/ plugins/ --glob '*.haml'` to enumerate.
* Prioritize: layout partials, helpers returning markup, cell output, admin
  views under `plugins/web_common/mount/app/views`.
* Grep helper methods that build HTML strings and return them into `=`.

### G. Legacy `#LT;` data - DECIDED: IGNORE
Old rows written through `make_hash_html_safe` may contain literal `#LT;`.
* No migration, no read shim. Such rows render their literal `#LT;` text; the
  volume is small / not worth carrying transition code.
* Just stop writing new `#LT;` (see C).

### H. Docs + specs
* `lib/overload/README.md` - rewrite the escaping section.
* Specs:
  - `String#unsafe` variants (default / script / style / true).
  - `Lux::Utils::SafeString#to_s` keeps `html_safe?` (regression guard for the
    `to_s` gotcha).
  - haml render: `= v` escaped, `= v.unsafe` raw-except-script/style,
    `.unsafe(true)` full. Extend `spec/lux_tests/template_render_spec.rb`.
  - JSON exporter: `<`/`>` -> `<`/`>`, round-trips through parse.
  - Attribute path still full-escapes (quote-injection guard).

## Decisions (settled)

1. Legacy `#LT;` rows: IGNORE (no migration, no shim).
2. `Lux::Utils::SafeString` is the class name (plural `Utils`, matching the
   existing `Lux::Utils::Json` / `Lux::Utils::Boolean` mixins).
3. Full test coverage required at each slice.

## Open decisions

1. JSON `.unsafe`: confirm no-op is acceptable (recommended).
2. Template audit: big-bang flip now vs framework-only + you migrate views.
3. Keep `html_safe`/`html_unsafe`/`html_escape` as deprecated aliases for one
   release, or hard-remove.

## Rollout order (low-risk first)

1. [DONE] A(partial) + B(patch only) - `Lux::Utils::SafeString`
   (`lib/lux/utils/safe_string.rb`), `String#unsafe` (`lib/overload/string.rb`,
   additive - old html_* trio left intact), `Haml::Util.escape_html_safe`
   override (`lib/lux/render/haml_escape.rb`, dormant until flip), specs
   (`spec/lib_tests/unsafe_spec.rb`, 19 examples). NO default flip.
2. D (JSON) - independent, low blast radius.
3. C (stop writing `#LT;`).
4. E (read-side callers) + remove old html_* trio.
5. F (template audit) + flip `escape_html: true` last, once views are tagged.
6. H docs.
