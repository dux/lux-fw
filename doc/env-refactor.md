# Environment Refactor - Design

Design doc for splitting `Lux::Environment` so the env name (where) is
separate from behavior toggles (how), and each can be set/overridden
independently. All design questions resolved (see §1.5); §4 is the spec.

## 1. What `Lux::Environment` does today

`lib/lux/environment/environment.rb` mixes four unrelated concerns into one
object:

| # | Concern | Methods | Source of truth |
|---|---------|---------|-----------------|
| 1 | Env name | `development?`, `dev?`, `production?`, `prod?`, `test?`, `to_s`, `==` | `RACK_ENV` |
| 2 | Process kind | `web?`, `cli?`, `rake?` | `$PROGRAM_NAME`, `ObjectSpace`, `LUX_WEB` |
| 3 | Deployment location | `live?`, `local?` | `LUX_LIVE` (gated by `cli?`) |
| 4 | Behavior flags | `log?`, `reload?` | `LUX_ENV` flag-string + `LUX_LOG` override |

Only #1 is really "environment". The rest are independent axes that happened
to live on the same object because there was nowhere else to put them.

### 1a. Where the inputs come from

```
RACK_ENV  = development | production | test     # env name
LUX_ENV   = "lr" | "clre" | "e" | ...           # opaque flag chars
LUX_LIVE  = true | false                        # deploy location
LUX_LOG   = true | false                        # override 'l' in LUX_ENV
LUX_WEB   = true | false                        # override web? detection
```

The `LUX_ENV` flag-string is the worst part. Examples from the repo:

* `bin/cli/console_hammer.rb:47` sets `LUX_ENV = 'clre'` (c=?, l=log, r=reload, e=?)
* `spec/spec_helper.rb:20` sets `LUX_ENV = 'e'` (e=?)
* `lib/lux/config/config.rb:43-46` mutates `LUX_ENV` in place based on `LUX_LOG`

`c` and `e` are read by nothing - they're vestigial. The semantics are smeared
across `environment.rb` and `config.rb`, and the format gives no room to grow.

### 1b. Confirmed bugs / wrinkles

* `live?` returns `false` whenever `cli?` is true (`environment.rb:37`).
  But the only real use of `LUX_LIVE` is in `plugins/job_runner/lib/lux_job.rb:53`,
  which reads `ENV['LUX_LIVE']` directly because `Lux.env.live?` doesn't work
  for a CLI worker. The abstraction is bypassed by its primary caller.
* `local?` is `!live?`, so a CLI process is always "local" - meaningless.
* `LUX_LOG=true|false` mutates the shared `LUX_ENV` string at boot. Order-
  dependent, side-effecty, and there's no equivalent for `reload`.
* `development?` returns `true` for `test` env (intentional, spec line 42),
  which trips people who reach for `Lux.env.dev?` expecting "strictly dev".

## 1.5. Decisions locked in

* **Namespace**: `Lux.mode` (not flat `Lux.log?` / `Lux.reload?`).
* **`live?` / `local?`**: removed. Nothing uses them through the abstraction.
  `LUX_LIVE` stays as a plain ENV var read directly where needed
  (`plugins/job_runner/lib/lux_job.rb:53` already does this).
* **`Lux.env.development?` / `dev?`**: keep current semantics
  (`!production?`, so true for both `development` and `test`).
* **`Lux.env.to_s`**: unchanged - returns raw env name (`"development"`,
  `"production"`, `"test"`).
* **`LUX_ENV` flag-string** (`"lr"`, `"clre"`, `"e"`): deleted. Replaced
  by per-flag ENV vars under `Lux.mode`.
* **`LUX_ENV` repurposed as the env name**, taking precedence over `RACK_ENV`.
  Resolution: `ENV['LUX_ENV'] || ENV['RACK_ENV'] || 'development'`. Default
  exists so quick-hack scripts work without RACK_ENV setup. Lives in
  `Lux::Environment.resolve_name`.
* **Boot banner reports env + mode** via `Lux::Config.start_info` -
  `Lux env: <name>` and `Lux mode: log (yes/no), errors (yes/no), reload (yes/no)`.
* **Initial mode flags**: `log?`, `errors?`, `reload?`. `errors?` is split
  out from `log?` so error visibility (response + console) can be toggled
  independently of routine console logging.
* **ENV overrides**: `LUX_LOG`, `LUX_ERRORS`, `LUX_RELOAD`. Case-insensitive
  (`.downcase`), accept only `"true"` / `"false"`. Empty string or unset =
  use env default. Any other value raises `ArgumentError` eagerly at boot
  (validated in `Lux::Mode.new`).
* **Runtime setter**: `Lux.mode.log = true` (and `errors=`, `reload=`).
  Overrides ENV. Useful for specs and `lux console`.
* **No `config.yaml mode:` block** for v1. ENV-only. Trivially additive
  later if a real need appears.

## 2. What the user wants

Quoting the request:

> env is basically where server runs, locally or on server, or is it testing,
> it should not have to do anything with "role". For example maybe we want
> screen logging and code reload in production, or we want full production
> speed in development. env can assume and set sane defaults for mode, but
> they must be able to be overridden.

So:

* **env** = name only (`dev | prod | test`), stays as-is.
* **Some other concept** = behavior toggles (`log`, `reload`, future:
  `cache`, `eager_load`, `debug`, ...), driven by env defaults but
  independently overridable.

The user asked for a better name than "role". Options below.

## 3. Naming options for concept #2

| Name | Pros | Cons |
|------|------|------|
| `mode` | Short, common, easy to read (`Lux.mode.log?`) | Generic; "dev mode" already overloaded |
| `profile` | Implies a named bundle of settings; switchable | Sounds like user/account profile |
| `flags` | Honest - that's what they are | Conflates with feature flags / experiments |
| `runtime` | Captures "how we run", not "what we are" | Already used in Ruby ecosystem (`RbConfig`) |
| `policy` | Suggests decisions ("log policy: verbose") | Heavy word |
| `traits` | Accurate (characteristics) | Vague |
| `tuning` | Implies adjustable knobs | Sounds perf-only |

**Chosen: `Lux.mode`.** Short, reads well at call sites, and the
"mode = behavior bundle, env = scope" split is intuitive. The alternative
(flat `Lux.log?` / `Lux.reload?`) was considered and dropped - cohesion
under `mode` outweighs the typing savings, and lets us add flags later
without polluting the `Lux` namespace.

## 4. Proposed split

Three small objects instead of one bag:

```
Lux.env       # name only: dev | prod | test
Lux.mode      # behavior toggles, with env-derived defaults + overrides
Lux.runtime   # process kind: web | cli | rake  (read-only, derived)
```

`live?` and `local?` are removed - nothing meaningful goes through them.

### 4a. `Lux.env` (slimmed)

```ruby
Lux.env                  # => Lux::Environment instance
Lux.env.to_s             # => "development" | "production" | "test"  (raw name, unchanged)
Lux.env.development?     # true unless production  (= !production?, current behavior)
Lux.env.dev?             # alias of development?
Lux.env.production?      # true only in production
Lux.env.prod?            # alias of production?
Lux.env.test?            # true in test (or under rspec/minitest)
Lux.env == :dev          # symbol/string comparison via predicate dispatch
```

Drop from this class entirely: `web?`, `cli?`, `rake?`, `live?`, `local?`,
`log?`, `reload?`. The `web?` / `cli?` / `rake?` methods move to
`Lux.runtime`; `log?` / `reload?` move to `Lux.mode`; `live?` / `local?`
are deleted.

### 4b. `Lux.mode`

`Lux.mode` is the home for **framework-wide behavior toggles**: knobs that
switch how the framework runs but are independent of which env it identifies
as.

**What belongs in mode (criteria):**

A flag goes in `Lux.mode` if and only if all of:

1. It's a boolean behavior switch consulted at runtime.
2. The "right" value usually correlates with env, but a user may legitimately
   want to flip it independently (e.g. `errors` on in prod for ad-hoc debugging).
3. It's framework-wide, not feature-specific. Per-feature toggles
   (`config.use_autoroutes`, etc.) stay in `Lux.config`.

**What does NOT belong in mode:**

* Process-kind detection (`web?`, `cli?`, `rake?`) - `Lux.runtime`.
* Env identity (`prod?`, `dev?`, `test?`) - `Lux.env`.
* Feature flags / experiments (those should be a separate `Lux.flags` if
  ever needed - not the same thing as mode).
* App config (DB URLs, API keys, timeouts) - `Lux.config`.

**Initial canonical set:**

```ruby
Lux.mode.log?         # screen dev logging (console only): Lux.log, cache hits, SQL echo, pretty JSON
Lux.mode.errors?      # error visibility on screen AND browser: dev backtrace in response, verbose 404s, console error log
Lux.mode.reload?      # per-request code reload (dev-style)
```

That's v1. We do NOT pre-design `cache?` / `pretty?` / `eager_load?` / `debug?` -
add them when a real call site needs them, with the same shape.

**Why `log?` and `errors?` are separate flags (and not bundled):**

Today `Lux.env.log?` gates three different kinds of behavior:

1. Routine console output (Lux.log, cache hits, SQL echo, pretty JSON) -> stays on `log?`.
2. Verbose 404/error messages in HTTP responses -> moves to `errors?`.
3. Console-logging of errors specifically (`error.rb:49`, `error/lux_adapter.rb:43`) -> moves to `errors?`.

The split enables the headline prod-debug stance: `LUX_LOG=false LUX_ERRORS=true`
- production stays quiet, but when something breaks you see *why* both in HTTP
responses and in logs. Flip `LUX_ERRORS=false` when done. The two flags carry the
same env defaults; the split is purely about override granularity.

**Defaults:**

| Flag    | dev | prod | test |
|---------|-----|------|------|
| log     | on  | off  | off  |
| errors  | on  | off  | off  |
| reload  | on  | off  | off  |

**ENV overrides:**

* `LUX_LOG`, `LUX_ERRORS`, `LUX_RELOAD`.
* Case-insensitive (`raw.downcase`).
* Only `"true"` and `"false"` accepted.
* Unset or empty string -> use env default (no error).
* Anything else (`"yes"`, `"1"`, `"on"`, ...) -> raise `ArgumentError` eagerly at
  boot in `Lux::Mode.new`. Bad config fails immediately, not later during a
  request.

**Runtime setter:**

```ruby
Lux.mode.log    = true     # overrides ENV
Lux.mode.errors = false
Lux.mode.reload = true
```

For specs and `lux console`. Per-instance state, no global mutation of ENV.

**Override precedence (lowest -> highest):**

```
env default  ->  ENV var  ->  runtime setter
```

**Use-case sanity check:**

* "Screen logging + reload in production" -> `LUX_LOG=true LUX_RELOAD=true bundle exec puma`
* "Production debugging via HTTP without log noise" -> `LUX_ERRORS=true bundle exec puma`
  (log? stays default off, errors? on, reload? stays default off)
* "Full prod speed in dev" -> `LUX_LOG=false LUX_ERRORS=false LUX_RELOAD=false bundle exec puma`
* "Silence test output" -> already the default (all three off in test).

**Implementation sketch:**

```ruby
module Lux
  class Mode
    FLAGS = {
      log:    { dev: true, prod: false, test: false, env: 'LUX_LOG' },
      errors: { dev: true, prod: false, test: false, env: 'LUX_ERRORS' },
      reload: { dev: true, prod: false, test: false, env: 'LUX_RELOAD' },
    }.freeze

    FLAGS.each_key do |name|
      define_method("#{name}?") { resolve(name) }
      define_method("#{name}=") { |v| @overrides[name] = !!v }
    end

    def initialize(env_name)
      @env_name  = env_name.to_s
      @env_key   = case @env_name
                   when 'production' then :prod
                   when 'test'       then :test
                   else                   :dev
                   end
      @overrides = {}
      @from_env  = {}

      # Eager validation: read + check all ENV vars upfront.
      FLAGS.each do |name, spec|
        raw = ENV[spec[:env]]
        next if raw.nil? || raw.empty?
        case raw.downcase
        when 'true'  then @from_env[name] = true
        when 'false' then @from_env[name] = false
        else raise ArgumentError,
          "#{spec[:env]}=#{raw.inspect} is invalid, expected 'true' or 'false'"
        end
      end
    end

    private

    def resolve(name)
      return @overrides[name] if @overrides.key?(name)
      return @from_env[name]  if @from_env.key?(name)
      FLAGS[name][@env_key]
    end
  end
end
```

Adding a new flag is one line in `FLAGS`. No string-parsing, no mutating
shared ENV.

**Call-site migration map:**

| Current | Becomes |
|---------|---------|
| `Lux.env.log?` at `lux.rb:30`, `cache.rb:170`, `db/load/logger.rb:31`, `overload/json.rb:4` | `Lux.mode.log?` |
| `Lux.env.log?` at `response.rb:325` (pretty JSON) | `Lux.mode.log?` (stays bundled; future `pretty?` if needed) |
| `Lux.env.dev? \|\| Lux.env.log?` at `controller.rb:121` (`show_dev`) | `Lux.mode.errors?` |
| `Lux.env.log?('404 ...') { ... }` at `template.rb:62,135`, `controller.rb:366,428`, `application.rb:207`, `routes.rb:59,166,227,231`, `response/lib/file.rb:76` | `Lux.mode.errors?('404 ...') { ... }` (block-form helper moves to Mode) |
| `Lux.log "..." if Lux.env.log?` at `error.rb:49`, `error/lux_adapter.rb:43` | `... if Lux.mode.errors?` |
| `Lux.env.reload?` at `response.rb:97`, `application.rb:87`, `assets/load/cdn_asset.rb:28`, `reloader.rb` | `Lux.mode.reload?` |

### 4c. `Lux.runtime` (rename of process-kind methods)

```ruby
Lux.runtime.web?    # running under puma/falcon/rackup/etc.
Lux.runtime.cli?    # !web?
Lux.runtime.rake?   # invoked via the rake binary
```

Pure detection from `$PROGRAM_NAME` + `ObjectSpace`, with `LUX_WEB` override
preserved. No env coupling.

## 5. Compatibility / migration

`Lux.env.log?` etc. have ~50 call sites (see `rg 'Lux\.env\.' lib plugins`).
Two routes:

**A. Hard break, single PR.** Rename callers via `ast-grep`/`rg --replace`.
Update `AGENTS.md` and the CLAUDE.md section. Spec rewrite is small.

**B. Shim period.** Keep `Lux.env.log?`, `Lux.env.web?`, etc. as deprecated
delegators to `Lux.mode.log?` / `Lux.runtime.web?` for one release. Cheaper
to land, but the conflation lingers.

This is an internal gem with a known set of consumer apps - leaning toward
**A** unless the user disagrees.

## 6. Resolved design questions

All resolved - see §1.5 for the locked-in decisions:

1. ~~Namespace~~ -> `Lux.mode`.
2. ~~Keep `live?` / `local?`~~ -> remove.
3. ~~`development?` semantics~~ -> keep current (`!production?`), `to_s` unchanged.
4. ~~`config.yaml mode:` block~~ -> no, ENV-only for v1. Adding YAML later is
   purely additive (new precedence layer between default and ENV).
5. ~~`LUX_ENV` flag-string~~ -> delete, replaced by per-flag ENV vars.
6. ~~Initial flag set~~ -> `log?`, `errors?`, `reload?`.
7. ~~ENV value parsing~~ -> case-insensitive, only `"true"`/`"false"`, empty=unset,
   anything else raises eagerly at boot.
8. ~~Runtime setter~~ -> yes (`Lux.mode.log = true`).

## 7. Files in scope

Framework code:

* `lib/lux/environment/environment.rb` - slim to env-name only (drop `web?`,
  `cli?`, `rake?`, `live?`, `local?`, `log?`, `reload?`).
* `lib/lux/environment/lux_adapter.rb` - add `Lux.mode` and `Lux.runtime`
  accessors next to existing `Lux.env`.
* New: `lib/lux/environment/mode.rb` - `Lux::Mode` class per §4b sketch.
* New: `lib/lux/environment/runtime.rb` - `Lux::Runtime` class per §4c.
* `lib/lux/config/config.rb:40-46` - drop `LUX_ENV` mutation and `LUX_LOG`
  patch block entirely.

Callers (renames):

* `Lux.env.log?` -> `Lux.mode.log?` (5 call sites, see §4b table).
* `Lux.env.log?(...) { ... }` block-form for verbose-404 messages
  -> `Lux.mode.errors?(...) { ... }` (~10 call sites). The block-form
  helper moves to `Lux::Mode`.
* `Lux.env.dev? || Lux.env.log?` (`controller.rb:121`) -> `Lux.mode.errors?`.
* `Lux.log "..." if Lux.env.log?` (`error.rb:49`, `error/lux_adapter.rb:43`)
  -> `... if Lux.mode.errors?`.
* `Lux.env.reload?` -> `Lux.mode.reload?` (8 call sites).
* `Lux.env.web?` / `cli?` / `rake?` -> `Lux.runtime.web?` / `cli?` / `rake?`
  (~15 call sites across `lib/lux/`, `plugins/db/`, `plugins/job_runner/`).

Boot scripts:

* `bin/cli/console_hammer.rb:47` - replace `LUX_ENV='clre'` with explicit
  `LUX_LOG=true LUX_ERRORS=true LUX_RELOAD=true` (or whatever the intent was).
* `bin/cli/server_hammer.rb:13,18` - same, drop `LUX_ENV` plumbing.
* `spec/spec_helper.rb:20` - replace `LUX_ENV='e'` with whatever it actually
  needs (likely nothing; `'e'` was a no-op flag char).

Specs:

* `spec/lux_tests/environment_spec.rb` - keep env-name + `==` + `to_s` tests;
  delete `log?` / `reload?` / `web?` / `cli?` tests (moved).
* New: `spec/lux_tests/mode_spec.rb` - defaults per env, ENV overrides
  (valid + invalid), runtime setter, eager validation raises.
* New: `spec/lux_tests/runtime_spec.rb` - web? / cli? / rake? detection.

Docs:

* `AGENTS.md` section "Lux::Environment" - rewrite into three sections:
  `Lux::Environment`, `Lux::Mode`, `Lux::Runtime`.
