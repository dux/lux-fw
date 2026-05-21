# Possible improvements

Cross-referenced against the top recurring complaints in Rails, Sinatra,
Hanami, and Roda over the last ~3-5 years (GitHub issues, blog posts,
HN/Reddit threads, conference talks). Each item notes which framework
faces the same pain or, conversely, which framework already solved it
in a way worth copying.

## Already strong (keep)

* Tree routing with `map` / `call` / `match` and `route.with_scope`
  (Roda-style cursor, no nav mutation)
* Plugin system with canonical layout (`loader.rb`, `load/`, `hammer/`,
  `mount/`) - better discoverability than Roda's flat plugin list
* Schema / type system (`lib/lux/schema`, `lib/lux/type`) - own flavor
  of the dry-rb territory Hanami occupies
* Policy proxy, `Lux.current` thread-local, JWT sessions
* Response API: `halt`, `etag`, `early_hints`, `send_file`, `auth`
* Exception logger with mountable viewer (Hanami / Sinatra miss this)
* API introspect + explorer with AGENTS.md emit (no other Ruby fw does
  this)
* Custom reloader that skips `Gem.path` - addresses the Rails
  "reload-degradation" complaint head-on

## Critical

Every framework gets burned here. lux-fw missing or thin.

* **No `routes` dump / introspection.** Rails, Sinatra, Roda all
  flagged; `map`/`call` graph is invisible. Add `bin/lux routes`
  printing the mounted tree (verb, path, target, source location).
* **CSRF protection unclear.** Grep finds nothing. Roda and Sinatra
  both criticized for opt-in CSRF. Needs first-class default-on for
  HTML form submissions (skip for JSON + Bearer).
* **No i18n / translations.** Only locale detection in `nav`. Rails
  and Hanami both bake it in; table-stakes for any SaaS.
* **No WebSocket / SSE / streaming primitive.** Sinatra and Roda need
  plugins, Rails has ActionCable. `response.stream { }` or
  `response.sse` would be ~50 LOC and a real differentiator given the
  rest of the stack is already Rack-clean.

## High

Top-three complaint in at least one framework.

* **Action-level params contract.** Implemented as the `opt` DSL plus a
  class-level `params do ... end` block on `Lux::Controller`. Both
  forms reuse `Lux::Schema::Define`, so the line parser is identical:

  ```ruby
  class UsersController < Lux::Controller
    # class-level: applies to every action in this class
    params do
      org_id   :uuid                   # shortcut form (method-missing -> set)
      api_key? :string                 # `?` suffix = optional
    end

    # method-level: applies to the next def only
    opt :name,  String, max: 30        # equivalent to: name String, max: 30
    opt :email, type: :email           # equivalent to: email type: :email
    opt :age,   Integer, req: false
    def create
      # current.params already coerced + validated, undeclared keys dropped
    end

    opt :term?, String
    def search; end

    def index; end                     # only class-level applies
  end
  ```

  Rule: allowed keys = (class `params do`) ∪ (method `opt` lines).
  Non-empty → strict (drop undeclared, validate required, coerce types).
  Empty → loose (pass-through, current behavior).

  Method-level `opt` wins on collision with class-level `params do`
  for the same key (Ruby method-override semantics).

  Both forms parse line args identically to `Lux::Schema::Define`:
  `foo Integer, max: 100` ≡ `set :foo, type: Integer, max: 100`.
* **Mailer previews.** Rails has it, everyone else is jealous. lux
  mailer is solid but no `/sys/mailer_previews` route.
* **Form to schema to error feedback loop.** `plugins/html/form`
  exists but no auto-binding to schema errors (Hanami does this
  cleanly with dry-validation).
* **Hot-reload edge cases.** The Rails complaint #1 is reloader
  breakage with custom containers / subclasses. Confirm lux reloader
  survives `Lux::*` constant redefinition, plugin reload, controller
  subclassing.
* **Generators are thin.** `bin/cli/generate_hammer.rb` exists but
  Sinatra/Roda complain loudest about scaffolding. Audit what it
  actually emits and expand (controller + spec + route + schema in
  one shot).
* **Dev error page context.** Roda's #1 complaint is unhelpful
  tracebacks. Verify `Lux::Error.render` shows request, params, source
  snippet, and reverse trace in dev.

## Medium

Recurring but lower frequency.

* **Dependency injection / slices.** Hanami's bounded-context story.
  lux has plugins but no per-mount isolated container. Probably not
  worth copying wholesale - flag, do not chase.
* **Job runner UX.** `plugins/job_runner` exists; verify retry,
  backoff, dead-letter handling. Sidekiq Web equivalent is a frequent
  ask.
* **Async / Falcon / fiber-friendly.** Rails finally got it. lux uses
  `Lux.delay` threads; fiber-safe `current` would future-proof.
* **API content-negotiation defaults.** Sinatra pain. lux/api seems
  to handle this; double-check JSON body parsing for
  `application/json` POST is default and not opt-in.
* **`rescue_from` granularity.** lux has it at app and controller
  level; verify per-exception-class matching like Rails.
* **Dev console with request replay.** Hanami and Rails both have it.
  `bin/lux console` exists but no "replay last request" affordance.
* **Test helpers shipping with framework.** Sinatra deprecated theirs;
  lux relies on rspec. A `Lux::Spec::Request` helper would help
  adoption.

## Low

Nice-to-have, structural, or not our problem.

* **Static types (Sorbet / RBS).** Ruby-wide problem. The schema/type
  system already covers runtime; shipping RBS files for the public
  surface would be a polish item.
* **Asset pipeline depth.** `plugins/assets/cdn_asset` is enough for
  the lux philosophy; do not chase Sprockets / Propshaft.
* **Multi-DB ergonomics.** Already covered via `Lux.db(:name)` -
  arguably better than Rails.
* **Onboarding docs.** README + AGENTS.md combo is ahead of Roda and
  Hanami; just keep filling holes.

## Top three if forced to pick

1. `bin/lux routes` - cheap, huge DX win, addresses a universal
   complaint
2. `opt` DSL + class-level `params do` on `Lux::Controller`,
   reusing `Lux::Schema::Define` for line parsing (Hanami-grade
   ergonomics on top of what we already have)
3. CSRF default-on plus a WebSocket / SSE primitive (modernization
   plus closing a real security gap)
