# Lux framework - LLM index

Ruby web framework. Rack + Sequel + PostgreSQL. Sinatra speed, Rails-shaped
controllers, Hanami-style schemas, **one shared DSL across controllers,
APIs, models, and schemas**.

This file is the agent index. Each subsystem has its own `AGENTS.md` next
to its README with one full example and module-specific rules. Read those
when working on the relevant code.

## Cross-cutting conventions (apply everywhere)

* **Inside `module Lux`**, `Hash` lexically resolves to `Lux::Hash`. Use
  `obj.is_hash?` (from `lib/overload/object.rb`) or fully-qualified
  `::Hash`. Same for any `Lux::<CoreClass>` alias.
* Use `FOO ||=` for module-level constants, not `FOO =`.
* End files with newline. No trailing spaces on blank lines.
* ASCII-only by default - prefer `-` over unicode dashes, `*` over `•`.
* No emojis in code or generated docs unless explicitly requested.
* Models use `ref` (string ULID) as primary key. Sequel-based ORM.
* `Lux.current` (alias `lux`) is the thread-local request context.

## The unified DSL

`Lux::Schema::Define` (`lib/lux/schema/define.rb`) is the shared line parser
used by:

* `Lux::Controller#opt` and `Lux::Controller.params`
* `Lux::Api.params`
* `Lux::Schema do ... end` standalone
* model `schema do ... end` blocks (via `plugins/db`)
* DB migration definitions

Line syntax (all equivalent):

```ruby
opt :name, String, max: 30                 # method-level (above def)
name String, max: 30                       # in-block shortcut
set :name, type: String, max: 30           # explicit
```

Field name suffix `?` marks the field optional. Default required.
Type vocabulary - any built-in (`String`, `Integer`, `Boolean`, ...) or a
named `Lux::Type` (`:email`, `:url`, `:uuid`, `:slug`, `:locale`, ...).

**When generating params code in any subsystem, use this DSL.** Do not
invent per-controller validators - the framework already wires the schema
through `Lux::Schema#validate(params, strict: true)` which drops undeclared
keys, validates required, coerces types.

## Where to look for each subsystem

| If user is touching... | Read first |
|------------------------|------------|
| HTTP routing / mount points | [`lib/lux/application/AGENTS.md`](./lib/lux/application/AGENTS.md) |
| Controller action / params  | [`lib/lux/controller/AGENTS.md`](./lib/lux/controller/AGENTS.md) |
| JSON API endpoint           | [`lib/lux/api/AGENTS.md`](./lib/lux/api/AGENTS.md) |
| Schema or model definition  | [`lib/lux/schema/AGENTS.md`](./lib/lux/schema/AGENTS.md) |
| Custom type / coercion      | [`lib/lux/type/AGENTS.md`](./lib/lux/type/AGENTS.md) |
| Access control              | [`lib/lux/policy/AGENTS.md`](./lib/lux/policy/AGENTS.md) |
| Request-scoped state        | [`lib/lux/current/AGENTS.md`](./lib/lux/current/AGENTS.md) |
| Response / headers / files  | [`lib/lux/response/AGENTS.md`](./lib/lux/response/AGENTS.md) |
| Rendering templates / cells | [`lib/lux/render/AGENTS.md`](./lib/lux/render/AGENTS.md) |
| Sending email               | [`lib/lux/mailer/AGENTS.md`](./lib/lux/mailer/AGENTS.md) |
| Caching                     | [`lib/lux/cache/AGENTS.md`](./lib/lux/cache/AGENTS.md) |
| Database / Sequel           | [`lib/lux/db/AGENTS.md`](./lib/lux/db/AGENTS.md) + [`plugins/db/AGENTS.md`](./plugins/db/AGENTS.md) |
| Errors / 4xx / 5xx          | [`lib/lux/error/AGENTS.md`](./lib/lux/error/AGENTS.md) |
| Localization / translations | [`lib/lux/locale/AGENTS.md`](./lib/lux/locale/AGENTS.md) |
| Env / mode / runtime        | [`lib/lux/environment/AGENTS.md`](./lib/lux/environment/AGENTS.md) |
| Config / `.env`             | [`lib/lux/config/AGENTS.md`](./lib/lux/config/AGENTS.md) |
| Plugin layout               | [`lib/lux/plugin/AGENTS.md`](./lib/lux/plugin/AGENTS.md) |
| Reloading                   | [`lib/lux/reloader/AGENTS.md`](./lib/lux/reloader/AGENTS.md) |
| Logger                      | [`lib/lux/logger/AGENTS.md`](./lib/lux/logger/AGENTS.md) |
| Shell / process / CLI output | [`lib/lux/shell/AGENTS.md`](./lib/lux/shell/AGENTS.md) |
| Hash / overloads            | [`lib/lux/hash/AGENTS.md`](./lib/lux/hash/AGENTS.md) |
| JSON export                 | [`lib/lux/json_exporter/AGENTS.md`](./lib/lux/json_exporter/AGENTS.md) |
| Templates engine            | [`lib/lux/template/AGENTS.md`](./lib/lux/template/AGENTS.md) |
| Reusable view component     | [`lib/lux/view_cell/AGENTS.md`](./lib/lux/view_cell/AGENTS.md) |

## Repo layout

```
lib/lux/<module>/         # core modules; each has README + AGENTS
lib/overload/             # Ruby core class extensions (don't touch lightly)
lib/common/               # Crypt, StringBase, StructOpts, TimeDifference
plugins/<name>/           # optional plugins, canonical layout (see plugin AGENTS)
spec/lux_tests/           # RSpec for framework features
spec/lib_tests/           # RSpec for pure-ruby utilities
bin/cli/<name>_hammer.rb  # CLI subcommands
```

## Documentation conventions

Every sub-module under `lib/lux/<name>/` ships **two** docs side-by-side:

| File | Audience | Shape |
|------|----------|-------|
| `README.md` | humans browsing GitHub | What it is → small example → full example → see-also |
| `AGENTS.md` | LLM agents | one canonical example → rules → don'ts → see-also |

### README.md shape (human-focused)

```markdown
# Lux::Foo

One- or two-sentence statement of what this module is and why it exists.
End with the differentiator (what makes it Lux-specific).

## Small example

The shortest piece of code that demonstrates the core value.
Three to five lines. No setup boilerplate.

## Full example

A realistic example showing every feature worth knowing. Comment groups
of related calls. Use `# ---` separators to break sections.

## (Optional sections in this order)

- API reference tables (`| method | notes |`)
- Configuration / options
- Conventions (file layout, naming)
- Limitations / known gaps

## See also

Relative links to sibling READMEs and this module's AGENTS.md, e.g.:
* [`../schema/README.md`](../schema/README.md) - the DSL parser
* [`AGENTS.md`](./AGENTS.md) - LLM guide
```

### AGENTS.md shape (LLM-focused)

```markdown
# Lux::Foo - agent guide

One sentence on the module's role. **Bold one sentence on the
prescriptive guidance** (e.g. "Reuse this everywhere a list of fields
needs validation").

## Canonical example

ONE example, end-to-end, showing the full feature surface. No "small
vs full" split - LLMs do better with one complete worked example than
multiple partial ones. Comment groups; mention edge cases inline.

## Rules

Bullet list. Each bullet leads with the rule, then a brief why. Cover:
* DSL forms / naming conventions
* Lifecycle / dispatch behavior
* What's automatic vs opt-in
* Cross-cutting conventions specific to this module

## Don't

Anti-patterns. Each bullet is one short sentence stating the mistake.
Include common mistakes you'd expect an LLM to make from
pattern-matching other frameworks.

## See also

Relative links to other AGENTS.md files for related modules.
```

### Rules for writing docs

* **GitHub-relative links.** Use `../foo/README.md`, `./AGENTS.md`,
  `../../../plugins/x/README.md`. Don't use absolute paths or HTTP URLs
  to the repo. Clicking the link in GitHub must navigate to the file.
* **One canonical example in AGENTS.md.** Multiple partial examples
  confuse LLMs more than they help. Make the single example complete.
* **No emojis** unless explicitly requested.
* **ASCII only.** Use `-` not `—`, `*` not `•`.
* **End files with newline.** No trailing spaces on blank lines.
* **Don't duplicate instructions** between README and AGENTS - README is
  the human reference, AGENTS is prescriptive ("use this", "don't do
  that"). README answers "how do I?", AGENTS answers "what's the right
  way?".
* **Cross-reference, don't repeat.** If `Lux::Controller` uses
  `Lux::Schema::Define`, link to the schema docs rather than re-explain
  the DSL.
* **Code examples use `ruby` fences.** Comments inside examples should
  read as a senior dev's notes, not LLM narration ("X does Y because Z",
  not "First we call X, then we call Y...").
* **Length:** READMEs 50-200 lines; AGENTS 30-100 lines. If longer,
  consider splitting the module.

## Adding code

* Edit an existing file in preference to creating a new one.
* Comment only the non-obvious why - never the what.
* When adding a feature, look for an existing primitive to reuse. The
  framework's whole reason for being is that the same primitives compose
  in every subsystem.
* Specs go under `spec/lux_tests/` for framework code, `spec/lib_tests/`
  for pure-ruby utilities. Run with `bundle exec rspec`.
* Never commit or push without explicit user instruction.

## When in doubt about a primitive

Check `Lux.schema(:name)` in `SCHEMA_STORE` for existing schemas. Check
`Lux::Type::*Type` under `lib/lux/type/types/` for existing types. Check
`Lux::Policy` descendants for existing policies. **Do not invent new
primitives that duplicate framework ones.**
