# Lux::Shell

Secure, ergonomic shell/process execution and status output. argv mode by
default; shell mode is explicit opt-in. Status helpers (`info`, `error`,
`die`) live here too so CLI hammer tasks can lean on one namespace.

POSIX-only. Windows is not supported.

## Small example

```ruby
Lux.shell.exec('git', 'status')                       # Result
Lux.shell.capture('git', 'rev-parse', 'HEAD')         # stripped stdout
Lux.shell.run('bundle', 'exec', 'rspec')              # boolean
Lux.shell.exec('git', 'push', raise: true)            # raise on failure
Lux.shell.info "deploy starting"
```

## Full example

```ruby
# argv mode (default) - no shell interpretation
r = Lux.shell.exec('curl', '-fsSL', user_supplied_url, timeout: 10)
r.success?         # boolean
r.exitstatus       # 0
r.out              # stdout string
r.err              # stderr string
r.duration         # seconds (Float)
r.lines            # stdout split on \n
r.timed_out?       # true if killed by timeout
r.json             # parse stdout as JSON (nil on parse error)

# block form - yielded on failure by default
Lux.shell.exec('aws', 's3', 'sync', src, dst) do |result|
  Lux.logger.error result.err
end

# on: :success / :always
Lux.shell.exec('rake', 'deploy', on: :always) { |r| audit(r) }

# raise instead of returning Result
Lux.shell.exec('git', 'push', raise: true)  # Lux::Shell::Error on non-zero

# env, chdir, stdin
Lux.shell.exec('bundle', 'install',
  env:   { 'BUNDLE_GEMFILE' => 'Gemfile.local' },
  chdir: './subapp')
Lux.shell.exec('mailx', '-s', 'hi', recipient, stdin_data: body)

# streaming lines (merged stdout+stderr)
Lux.shell.stream('tail', '-f', './log/app.log') { |line| puts line }

# locate binaries
Lux.shell.which('ffmpeg')      # "/opt/homebrew/bin/ffmpeg" or nil
Lux.shell.exists?('ffmpeg')    # boolean

# status output to STDERR
Lux.shell.info  'deploy starting'
Lux.shell.error 'deploy failed'
Lux.shell.die   'config missing'   # logger.fatal + exit 1
```

## Security model

* **Default is argv.** `Lux.shell.exec('cmd', a, b, ...)` invokes the binary
  directly via `Open3` - no shell, no metacharacter interpretation.
  Interpolating untrusted values into argv is safe; they cannot escape.
* **Shell mode is explicit.** `shell: true` accepts a single string and
  runs it via `/bin/sh -c`. Multiple-argv + `shell: true` raises - that
  combination is almost always a mistake.
* **Escape interpolated values in shell mode** using `String#shellescape`:

  ```ruby
  Lux.shell.run "pg_dump #{url.shellescape} > #{path.shellescape}", shell: true
  ```

* **Never interpolate user input into a shell-mode command.** If the value
  comes from outside the process, use argv mode and let Ruby pass it
  literally.

## API

| call | returns | notes |
|------|---------|-------|
| `exec(*argv, **opts, &block)` | `Result` | core primitive |
| `capture(*argv, **opts)` | `String` | stripped stdout, raises on failure unless block |
| `run(*argv, **opts)` | `Boolean` | success? |
| `stream(*argv, **opts) { \|line\| ... }` | `Result` | merged stdout+stderr line callback |
| `which(name)` | `String?` | absolute path or nil |
| `exists?(name)` | `Boolean` | `!which.nil?` |
| `info(text)` | nil | magenta status to STDERR; accepts an Array |
| `error(text)` | nil | red status to STDERR; accepts an Array |
| `die(text)` | (no return) | `logger.fatal` + `exit 1` |

### Options accepted by `exec`/`capture`/`run`/`stream`

| key | default | notes |
|-----|---------|-------|
| `env:` | `{}` | merged into child env |
| `chdir:` | nil | working directory |
| `stdin_data:` | nil | string piped into child stdin |
| `timeout:` | nil | seconds; child is `SIGKILL`-ed on expiry |
| `shell:` | false | route through `/bin/sh -c`; requires a single string argv |
| `raise:` | false | raise `Lux::Shell::Error` on non-zero exit (`exec` only) |
| `on:` | `:failure` | block trigger - `:failure`, `:success`, or `:always` |

### `Result`

| reader | notes |
|--------|-------|
| `command` | argv that was run |
| `out` / `err` | captured streams |
| `status` | `Process::Status` (or stand-in if command not found) |
| `exitstatus` | integer or nil |
| `success?` | `!timed_out? && status.success?` |
| `timed_out?` | true if the timeout fired |
| `duration` | seconds (Float) |
| `lines` | `out.lines.map(&:chomp)` |
| `strip` | `out.strip` |
| `out!` | `out.strip` or raise `Lux::Shell::Error` |
| `err?` | non-empty stderr |
| `json` / `json!` | parse stdout as JSON (nil vs raise) |
| `to_h` / `inspect` | structured / human display |

### `Lux::Shell::Error`

Raised by `exec(raise: true)` and `Result#out!`. Carries the full `Result`
via `.result`, so callers can inspect stdout/stderr/exit/duration.

## See also

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`../logger/README.md`](../logger/README.md) - `Lux.logger` (used by `die`)
