> STATUS: DONE / shipped. Lux::Utils::HtmlTag is vendored and in use; this note is kept for history.

## utils-html-tag

Vendor the `html-tag` gem source into `lib/lux/utils/` as `Lux::Utils::HtmlTag`,
drop the external dependency entirely, and document it like every other
`Lux::Utils::*` member.

### Current state

* gemspec: `gem.add_dependency 'html-tag'`
* `lib/lux/boot.rb`: `require 'html-tag'`
* Gem source (v3.0.6) has three files:
  * `html-tag/html_tag.rb` - top-level `HtmlTag` module + `method_missing` proxy
  * `html-tag/inbound.rb`  - `HtmlTag::Inbound` builder (the real work)
  * `html-tag/globals.rb`  - global `HtmlTag()` function, `Hash#tag`, `String#tag`,
    `HtmlTag::Proxy`
* Used as `HtmlTag.div { ... }`, `include HtmlTag`, `HtmlTag self` (mixin),
  and `Hash#tag` / `String#tag` monkey-patches.
* Call sites:
  * `lib/lux/error/error.rb` -> `HtmlTag.html { ... }`, `HtmlTag.pre { ... }`
  * `lib/lux/view_cell/view_cell.rb` -> `include HtmlTag`
  * `plugins/web_common/load/html/html_filter.rb` -> `HtmlTag self`
  * `plugins/web_common/load/html/input/html_input.rb` -> `HtmlTag *args, &block`
  * `plugins/web_common/load/html/table/html_table*.rb` -> `HtmlTag.div`, `HtmlTag.span`, etc.
  * `plugins/web_common/load/html/form/html_form_custom.rb` -> `HtmlTag.button { ... }`

### Goal

* Remove `gem.add_dependency 'html-tag'` from `lux-fw.gemspec`.
* Remove `require 'html-tag'` from `lib/lux/boot.rb`.
* Vendor the gem source under `Lux::Utils::HtmlTag`.
* Keep top-level `HtmlTag` constant and bare `HtmlTag(...)` function as
  back-compat aliases - no call-site rewrites required.
* Move `Hash#tag` / `String#tag` into `lib/overload/`.
* Document in `lib/lux/utils/README.md`.

---

## Plan

### Files added
* `lib/lux/utils/html_tag/html_tag.rb` - defines `module Lux::Utils::HtmlTag`
  (the `extend self` proxy module, equivalent to the gem's top-level `HtmlTag`).
* `lib/lux/utils/html_tag/inbound.rb`  - `Lux::Utils::HtmlTag::Inbound` builder.
* `lib/lux/utils/html_tag/globals.rb`  - defines:
  * `HtmlTag = Lux::Utils::HtmlTag` (top-level alias)
  * `def HtmlTag(*args, &block)` top-level function (delegates to
    `Lux::Utils::HtmlTag::Proxy` / class injector, same semantics as gem)
  * `Lux::Utils::HtmlTag::Proxy`

Folder layout under `lib/lux/utils/html_tag/` is the first sub-folder in
`utils/`; `Dir.require_all` already recurses, so no explicit `require_relative`
chain is required, but we'll add one inside the folder for predictable order
(`html_tag.rb` -> `inbound.rb` -> `globals.rb`).

### Files modified
* `lux-fw.gemspec` - drop `gem.add_dependency 'html-tag'`.
* `lib/lux/boot.rb` - drop `require 'html-tag'`.
* `lib/overload/hash.rb` - add `Hash#tag` (dispatches to
  `Lux::Utils::HtmlTag::Inbound.new.tag(node_name, inner_html, self, &block).join('')`).
* `lib/overload/string.rb` - add `String#tag` (same pattern).
* `lib/lux/utils/README.md`:
  * Add row: `| Lux::Utils::HtmlTag | html_tag/ | tag-based HTML builder (vendored
    html-tag gem) - aliased as top-level HtmlTag |`
  * Add example block matching the style of `Crypt`/`StringBase`/etc:
    builder form, mixin form, monkey-patch form, custom tag registration.

### Files untouched
* All call sites (`lib/lux/error/error.rb`, `lib/lux/view_cell/view_cell.rb`,
  `plugins/web_common/load/html/...`) - they keep `HtmlTag.xxx` / `include HtmlTag` /
  `HtmlTag self` / `HtmlTag *args, &block`, served by the top-level alias and
  bare function.

### Tests
* Add a spec under `spec/lux_tests/` exercising:
  * `Lux::Utils::HtmlTag.div { ... }` renders.
  * `HtmlTag.div { ... }` renders (alias path).
  * `HtmlTag(:ul) { li "x" }` (bare function with block).
  * `{ class: 'x' }.tag(:div, 'y')` (Hash#tag).
  * `'inner'.tag(:p)` (String#tag).
  * `class Foo; HtmlTag self; end; Foo.new.tag(:span) { 'x' }` (mixin).
  * `HtmlTag::Inbound.define :foo` adds a tag.

---

## Decided

### Q1. Doc filename
`doc/feature/utils-html-tag.md`.

### Q2. Namespace exposure
Alias only - `Lux::Utils::HtmlTag` (no wrapper module).

### Q3. `Lux.*` shim
No shim. Use `Lux::Utils::HtmlTag` (or the top-level alias).

### Q4. External dep + file layout
Drop the gem dependency and the `require 'html-tag'` line. Vendor under
`lib/lux/utils/html_tag/` as three files mirroring the gem
(`html_tag.rb`, `inbound.rb`, `globals.rb`).

### Q5. Top-level API
Keep both: `HtmlTag = Lux::Utils::HtmlTag` and the bare `HtmlTag(...)` function.
Zero call-site changes.

### Q6. Stdlib patches
`Hash#tag` and `String#tag` move into `lib/overload/hash.rb` and
`lib/overload/string.rb` (dispatching to `Lux::Utils::HtmlTag::Inbound`),
matching how other utils install their monkey-patches.

### Q7. README
Add a row + dedicated example block.

### Q8. Custom tag pre-registration
None. Tag set left untouched; apps register what they need.

---

## Skipped / not sure

(none)
