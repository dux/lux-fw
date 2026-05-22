# Lux::Shell

Secure, ergonomic shell/process execution and status output. argv mode by
default; shell mode is explicit opt-in. Status helpers (`info`, `error`,
`die`) live here too so CLI hammer tasks can lean on one namespace.

POSIX-only. Windows is not supported.

## Small example

```ruby
Lux.shell.exec('git', 'rev-parse', 'HEAD')         # stripped stdout, raises on failure
Lux.shell('createdb', 'mydb')                      # Lux.shell(*argv) is shorthand for .exec
Lux.shell.capture('bundle', 'install')             # merged stdout+stderr, never raises
Lux.shell.exec('rspec') { |err, _| log err }       # block handles failure -> returns nil
Lux.shell.info "deploy starting"
```

## Full example

```ruby
# argv mode (default) - no shell interpretation
out = Lux.shell.exec('curl', '-fsSL', user_supplied_url, timeout: 10)
# out is the stripped stdout; a failure (non-zero, timeout, ENOENT) raises
# Lux::Shell::Error unless you provide a block.

# block on failure - receives (stderr, stdout); return value of exec is nil
Lux.shell.exec('aws', 's3', 'sync', src, dst) do |err, out|
  Lux.logger.error err
end

# silent failure - empty block swallows everything
Lux.shell.exec('maybe-missing') {}

# env / chdir / stdin / timeout
Lux.shell.exec('bundle', 'install',
  env:   { 'BUNDLE_GEMFILE' => 'Gemfile.local' },
  chdir: './subapp')
Lux.shell.exec('mailx', '-s', 'hi', recipient, stdin_data: body)
Lux.shell.exec('sleep', '5', timeout: 0.5)         # raises with /timed out/

# shell mode - opt-in, single string only
Lux.shell.exec("pg_dump #{url.shellescape} > #{path.shellescape}", shell: true)

# capture - merged streams, never raises; for "give me whatever happened"
buffer = Lux.shell.capture("grep -i foo ./log/app.log 2>/dev/null | tail -100", shell: true)

# streaming lines (merged stdout+stderr)
Lux.shell.stream('tail', '-f', './log/app.log') { |line| puts line }

# locate binaries
Lux.shell.which('ffmpeg')      # "/opt/homebrew/bin/ffmpeg" or nil
Lux.shell.exists?('ffmpeg')    # boolean

# status output to STDERR (STDOUT stays clean for piping)
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
  Lux.shell "pg_dump #{url.shellescape} > #{path.shellescape}", shell: true
  ```

* **Never interpolate user input into a shell-mode command.** If the value
  comes from outside the process, use argv mode and let Ruby pass it
  literally.

## API

| call | returns | failure behaviour |
|------|---------|-------------------|
| `exec(*argv, **opts, &block)` | stripped stdout | raises `Lux::Shell::Error`; or calls `block.(err, out)` and returns nil |
| `capture(*argv, **opts)` | merged stdout+stderr (unstripped) | never raises |
| `stream(*argv, **opts) { \|line\| ... }` | merged output | never raises |
| `Lux.shell(*argv, **opts, &block)` | same as `exec` | shorthand on the `Lux` module |
| `which(name)` | `String?` | absolute path or nil |
| `exists?(name)` | `Boolean` | `!which.nil?` |
| `info(text)` | nil | magenta status to STDERR; accepts an Array |
| `error(text)` | nil | red status to STDERR; accepts an Array |
| `die(text)` | (no return) | `logger.fatal` + `exit 1` |

### Options

| key | default | applies to | notes |
|-----|---------|------------|-------|
| `env:` | `{}` | exec, capture, stream | merged into child env |
| `chdir:` | nil | exec, capture, stream | working directory |
| `stdin_data:` | nil | exec, capture | string piped into child stdin |
| `timeout:` | nil | exec | seconds; child is `SIGKILL`-ed on expiry, counts as failure |
| `shell:` | false | exec, capture, stream | route through `/bin/sh -c`; requires a single string argv |

### `Lux::Shell::Error`

Raised by `exec` when the command fails and no block was given. Carries:

| reader | notes |
|--------|-------|
| `command` | the argv that was run |
| `err` | stderr (or `"timed out after Ns"` on timeout, or the ENOENT message) |
| `out` | stdout at the point of failure |

## See also

* [`AGENTS.md`](./AGENTS.md) - LLM guide
* [`../logger/README.md`](../logger/README.md) - `Lux.logger` (used by `die`)
