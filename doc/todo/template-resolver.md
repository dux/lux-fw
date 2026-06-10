# Template resolver chain

## Request

When `Lux::Template` can't find a view file on disk, instead of immediately
raising 404, give registered functions a chance to supply the template from
elsewhere (another directory, a DB, generated source). This is a
value-returning, ordered, first-hit-wins chain - not a fire-and-forget event.

Mirrors two existing patterns:
* locale plugin's `registered handler -> external store -> flat-file` chain
  (`./plugins/locale/load/locale.rb:238`)
* `Ref`'s `REGISTRY ||= {}` + `register` (`./plugins/db/lib/ref.rb:32`)

## Design decisions

1. Resolver return contract - each resolver is `->(path) { ... }` receiving the
   extension-less path Lux looked for, returning one of:
   * `String` - a full file path WITH extension elsewhere (resolver does its own
     `Dir[...][0]`, like `find_layout` already does) -> `Tilt.new(path)`
   * `Tilt` object - a ready template (DB-stored / generated source) -> used directly
   * `nil` - not handled, try next resolver (else 404)
2. Scope - views only (`compile_template`). Layouts (`find_layout`) and the
   controller `_ref` existence probe (`template_file_exists?`) stay file-only.
   Resolvers are a render-time fallback, not part of probing. Easy to extend to
   layouts later.
3. Registration stays explicit (matches no-boot-magic preference):
   `Lux::Template.resolvers << ->(path) { ... }`

Open follow-ups to confirm before/while implementing:
* Should a `String` result be allowed extension-less (framework re-probes
  extensions) for ergonomics? Current plan: require extension, minimal diff.
* Extend to `find_layout` (layouts) too? Current plan: no.

## Planned code changes

### 1. `./lib/lux/template/template.rb`

(a) Constant in the class body, right after `class Template` (line 2).
Class-body scope so `Lux::Template::RESOLVERS` resolves; a constant inside
`class << self` would land on the singleton instead.

```ruby
module Lux
  class Template
    # Fallback resolvers, tried in order when no template file exists on disk.
    # Register from app/plugin code:  Lux::Template.resolvers << ->(path) { ... }
    RESOLVERS ||= []          # why: ordered fallback chain, first non-nil wins

    class << self
```

(b) Two methods at the end of the `class << self` block, after `tilt_extensions`
(after line 73):

```ruby
      # Registered fallback resolvers (see RESOLVERS). Append a callable:
      #   Lux::Template.resolvers << ->(path) { "#{other_dir}/#{File.basename path}.haml" }
      # Each receives the extension-less template path and returns one of:
      #   * String - full path (with extension) to a template file elsewhere
      #   * Tilt   - a ready template object (DB-stored / generated source)
      #   * nil    - not handled; try the next resolver
      def resolvers
        RESOLVERS
      end

      # Walk the chain on a miss; first non-nil result wins, nil if none match.
      def resolve path
        RESOLVERS.each do |resolver|
          result = resolver.call(path)
          return result if result
        end
        nil
      end
```

(c) Replace the hard-404 tail of `compile_template` (current lines 144-149):

```ruby
    # BEFORE
    unless @template
      raise Lux.error 404, Lux.mode.debug?('404 Not Found') { %[Lux::Template "#{template}.{erb,haml}" not found] }
    end

    @tilt = Tilt.new(@template, escape_html: false)
    pointer[template] = [@tilt, @template]
```

```ruby
    # AFTER
    if @template
      @tilt = Tilt.new(@template, escape_html: false)
    elsif (resolved = Lux::Template.resolve(template))   # why: fallback chain before 404
      if resolved.is_a?(String)
        @template = resolved                              # path to a file elsewhere
        @tilt     = Tilt.new(@template, escape_html: false)
      else
        @template = template                              # keep logical name for files_in_use/debug
        @tilt     = resolved                              # resolver returned a ready Tilt object
      end
    else
      raise Lux.error 404, Lux.mode.debug?('404 Not Found') { %[Lux::Template "#{template}.{erb,haml}" not found] }
    end

    pointer[template] = [@tilt, @template]                # why: cache resolver hits too, same as files
```

Resolver hits flow through the existing cache line: in production a resolved
template compiles once (same trade-off as files). In dev/test the cache is
per-request, so edits stay live.

### 2. `./spec/lux_tests/template_render_spec.rb`

New `describe` block before the final `end`. Reuses the existing `build_helper`
/ `views` helpers and the `shared/_widget` fixture. `after` clears the global
chain so tests don't leak.

```ruby
  describe 'fallback resolvers' do
    after { Lux::Template.resolvers.clear }   # why: RESOLVERS is process-global

    it 'resolves a miss to a file path returned by a resolver' do
      Lux::Template.resolvers << ->(path) { "#{views}/shared/_widget.haml" if path.end_with?('ghost') }
      result = build_helper.render "#{views}/pages/ghost"
      _(result).must_include 'shared:widget'
    end

    it 'renders a Tilt template returned by a resolver' do
      Lux::Template.resolvers << ->(path) { Tilt['erb'].new { 'resolved-<%= 1 + 1 %>' } if path.end_with?('virtual') }
      result = build_helper.render "#{views}/pages/virtual"
      _(result).must_include 'resolved-2'
    end

    it 'tries resolvers in order, first non-nil wins' do
      Lux::Template.resolvers << ->(_)    { nil }
      Lux::Template.resolvers << ->(path) { Tilt['erb'].new { 'second' } if path.end_with?('chain') }
      _(build_helper.render("#{views}/pages/chain")).must_include 'second'
    end

    it 'still 404s when no resolver matches' do
      _(-> { build_helper.render "#{views}/pages/missing_for_sure" }).must_raise Lux::Error
    end
  end
```

### 3. `./lib/lux/template/README.md`

Short section after "Conventions" (line 55):

```markdown
## Fallback resolvers

When no template file exists, registered resolvers are tried in order before
a 404 is raised. Each receives the extension-less path and returns a file path
(with extension), a ready `Tilt` template, or `nil` to pass:

    Lux::Template.resolvers << ->(path) do
      file = Dir["./themes/active/#{File.basename path}.*"].first
      file || (src = DB.template(path) and Tilt['erb'].new { src })
    end

Resolved templates are cached like files (compiled once in production).
```

## Validation

* `bin/rspec spec/lux_tests/template_render_spec.rb` (or project runner)
* `ruby -c lib/lux/template/template.rb`

## Notes

* ~30 lines of feature code, contained to the existing miss-branch + two small
  class methods. No new files, no new fixtures, no changes to callers.
* `Lux::Error < StandardError` (`./lib/lux/error/error.rb:9`), so the 404 test
  asserts `must_raise Lux::Error`.
