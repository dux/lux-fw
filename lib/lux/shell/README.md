# Lux::Shell

Secure, ergonomic shell/process execution and status output. argv mode by
default; shell mode is explicit opt-in. Status helpers (`info`, `error`,
`die`) live here too so CLI hammer tasks can lean on one namespace.

POSIX-only. Windows is not supported.

## Full example

```ruby
# --- exec: returns stripped stdout; raises Lux::Shell::Error on any failure
sha = Lux.shell.exec('git', 'rev-parse', 'HEAD')         # "abc1234..."

# Shortcut: Lux.shell(*argv, **opts, &block) === Lux.shell.exec(...)
Lux.shell 'createdb', 'mydb'                             # raises on non-zero

# Block handles the failure path; gets (stderr, stdout); exec returns nil
Lux.shell.exec('aws', 's3', 'sync', src, dst) do |err, _out|
  Lux.logger.error err
end

# Empty block = silent failure
Lux.shell.exec('maybe-missing') {}

# --- options: env / chdir / stdin / timeout (timeout counts as failure)
Lux.shell.exec('cat', stdin_data: body, chdir: '/tmp',
               env: { 'TZ' => 'UTC' }, timeout: 5)

# --- shell mode: opt-in, single string, shellescape interpolated values
Lux.shell "pg_dump #{url.shellescape} > #{file.shellescape}", shell: true

# --- capture: merged stdout+stderr, never raises (use when exit code isn't the signal)
buffer = Lux.shell.capture("grep -i foo ./log/app.log 2>/dev/null", shell: true)

# --- stream: line-by-line consumption; returns merged collected output
Lux.shell.stream('tail', '-f', './log/app.log') { |line| puts line }

# --- locate binaries
Lux.shell.which('ffmpeg')                                # "/opt/homebrew/bin/ffmpeg" or nil
Lux.shell.exists?('git')                                 # true / false

# --- status output (STDERR; STDOUT stays clean for piping)
Lux.shell.info  'deploy starting'                        # magenta
Lux.shell.error 'deploy failed'                          # red
Lux.shell.die   'config missing'                         # logger.fatal + exit 1
```

## Security model

* **Default is argv.** `Lux.shell.exec('cmd', a, b, ...)` invokes the binary
  directly via `Open3` - no shell, no metacharacter interpretation.
  Interpolating untrusted values into argv is safe.
* **Shell mode is explicit.** `shell: true` accepts a single string and
  runs it via `/bin/sh -c`. Multiple-argv + `shell: true` raises.
* **Escape interpolated values in shell mode** with `String#shellescape`.

## API

| call | returns | failure |
|------|---------|---------|
| `Lux.shell.exec(*argv, **opts, &block)` | stripped stdout | raises `Lux::Shell::Error`; or calls `block.(err, out)` and returns nil |
| `Lux.shell(*argv, **opts, &block)` | same | shorthand for `.exec` |
| `Lux.shell.capture(*argv, **opts)` | merged stdout+stderr (unstripped) | never raises |
| `Lux.shell.stream(*argv, **opts) { \|line\| ... }` | merged output | never raises |
| `Lux.shell.which(name)` | absolute path or nil | |
| `Lux.shell.exists?(name)` | Boolean | |
| `Lux.shell.info(text)` | nil | magenta status to STDERR; accepts Array |
| `Lux.shell.error(text)` | nil | red status to STDERR; accepts Array |
| `Lux.shell.die(text)` | (no return) | `logger.fatal` + `exit 1` |

### Options accepted by exec / capture / stream

| key | default | applies to | notes |
|-----|---------|------------|-------|
| `env:` | `{}` | all | merged into child env |
| `chdir:` | nil | all | working directory |
| `stdin_data:` | nil | exec, capture | string piped into child stdin |
| `timeout:` | nil | exec | seconds; child is `SIGKILL`-ed on expiry; counts as failure |
| `shell:` | false | all | route through `/bin/sh -c`; requires a single string argv |

### `Lux::Shell::Error`

Raised by `exec` on failure when no block was given. Carries:

| reader | notes |
|--------|-------|
| `command` | the argv that was run |
| `err` | stderr (or `"timed out after Ns"` on timeout, or the ENOENT message) |
| `out` | stdout at the point of failure |

## See also

* [`../logger/README.md`](../logger/README.md) - `Lux.logger` (used by `die`)
