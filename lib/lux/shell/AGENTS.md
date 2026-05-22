# Lux::Shell - agent guide

Secure shell/process execution + status output. **argv mode is the only safe
default**; `shell: true` is opt-in and visually obvious at the call site.

## Canonical example

```ruby
# argv (default) - safe, no shell interpretation. Returns stripped stdout;
# raises Lux::Shell::Error on any failure (non-zero exit, timeout, ENOENT).
sha = Lux.shell.exec('git', 'rev-parse', 'HEAD')

# Shortcut: Lux.shell(*argv, **opts, &block) is exactly Lux.shell.exec(...)
Lux.shell 'createdb', name

# Block handles the failure path; gets (stderr, stdout); exec returns nil
Lux.shell.exec('aws', 's3', 'sync', src, dst) do |err, _out|
  Lux.logger.error err
end

# Empty block = silent failure
Lux.shell.exec('maybe-missing') {}

# Merged stdout+stderr, NEVER raises. Use when you want "everything that
# happened" and intend to grep/inspect the buffer yourself.
buffer = Lux.shell.capture("grep -i foo ./log/app.log 2>/dev/null", shell: true)

# env / chdir / stdin / timeout (timeout counts as failure)
Lux.shell.exec('cat', stdin_data: body, chdir: '/tmp',
               env: { 'TZ' => 'UTC' }, timeout: 5)

# Line-by-line during execution; returns merged collected output
Lux.shell.stream('tail', '-f', './log/app.log') { |l| puts l }

# Locate binaries
Lux.shell.which('ffmpeg')     # path or nil
Lux.shell.exists?('git')      # boolean

# Status output (STDERR; STDOUT stays clean for piping)
Lux.shell.info  'deploy starting'
Lux.shell.error 'deploy failed'
Lux.shell.die   'config missing'   # logger.fatal + exit 1

# shell mode - opt-in, single string only
Lux.shell "pg_dump #{url.shellescape} > #{file.shellescape}", shell: true
```

## Rules

* **Default to argv.** `Lux.shell.exec('cmd', user_value)` is injection-safe
  because the binary is spawned directly via `Open3`. Use this for anything
  that takes external input.
* **`shell: true` is opt-in and visible.** Reach for it only for pipes,
  redirects, command substitution, or env-var prefixes. Always
  `String#shellescape` interpolated values inside a shell-mode command.
* **`shell: true` rejects multi-argv calls** - it would silently quote each
  arg, hiding intent. Pass a single string.
* **exec raises by default.** No `raise:` option, no `on:` option. If you
  want to swallow / handle the failure, supply a block - empty block is
  legitimate "silent" syntax.
* **Block signature is `(stderr, stdout)`** - stderr first because it is the
  failure-relevant stream. Return value is ignored; exec returns nil on
  failure.
* **`capture` never raises.** It is the explicit "I want the buffer
  regardless" tool. Merged stdout+stderr, returned unstripped. Use for log
  greps, diagnostics, anything where the exit code isn't the signal you
  care about.
* **Status helpers** (`info`, `error`, `die`) write to STDERR so CLI output
  pipelines stay clean.
* **`stream`** is for line-by-line consumption of long-running commands;
  stdout and stderr are merged.
* **POSIX only.** No Windows fallback paths.

## Don't

* Don't use backticks or `Kernel.system("#{cmd}")` - they hide whether
  shell expansion happens and leak injection-prone interpolation.
* Don't use `shell: true` with user-supplied data unless you `shellescape`
  every interpolated value - and prefer argv mode in that case anyway.
* Don't reach for `Open3.*` directly in app code - `Lux.shell.exec` already
  wraps it with timeout, structured errors, and stripped output.
* Don't put `Lux.shell.info` calls in hot request paths - it's for CLI/boot
  status, not request logging (use `Lux.logger` for that).
* Don't `rescue Lux::Shell::Error` and silently drop it; either let it
  bubble or log `e.err` so the cause is recoverable.
* Don't reach for `capture` when you actually want failures to surface -
  use `exec`. `capture` is for buffer-then-inspect, not for fire-and-check.

## See also

* [`README.md`](./README.md) - human-facing API reference
* [`../logger/AGENTS.md`](../logger/AGENTS.md) - `Lux.logger`, used by `die`
