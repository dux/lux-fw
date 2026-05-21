# Lux::Shell - agent guide

Secure shell/process execution + status output. **argv mode is the only safe
default**; `shell: true` is opt-in and visually obvious at the call site.

## Canonical example

```ruby
# argv (default) - safe, no shell interpretation
Lux.shell.exec('git', 'status')
Lux.shell.capture('git', 'rev-parse', 'HEAD')           # stripped stdout
Lux.shell.run('bundle', 'exec', 'rspec')                # boolean
Lux.shell.exec('git', 'push', raise: true)              # raise on failure

# block yields the Result; default trigger is :failure
Lux.shell.exec('aws', 's3', 'sync', src, dst) do |result|
  Lux.logger.error result.err
end
Lux.shell.exec('rake', 'task', on: :always) { |r| audit r }

# env / chdir / stdin / timeout
Lux.shell.exec('cat', stdin_data: body, chdir: '/tmp',
               env: { 'TZ' => 'UTC' }, timeout: 5)

# streaming lines (merged stdout+stderr)
Lux.shell.stream('tail', '-f', './log/app.log') { |l| puts l }

# locate binaries
Lux.shell.which('ffmpeg')     # path or nil
Lux.shell.exists?('git')      # boolean

# status output (STDERR; STDOUT stays clean for piping)
Lux.shell.info  'deploy starting'
Lux.shell.error 'deploy failed'
Lux.shell.die   'config missing'   # logger.fatal + exit 1

# shell mode - opt-in, single string only
Lux.shell.run "pg_dump #{url.shellescape} > #{file.shellescape}", shell: true
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
* **`raise: true`** turns a non-zero exit into `Lux::Shell::Error` (which
  carries `.result`). Use it for fail-fast wiring; otherwise inspect
  `result.success?`.
* **Block + raise combo:** the block fires before `raise`; you can swallow
  the error by setting `raise: false` (the default with a block).
* **`capture`** auto-raises on failure unless a block is given (which signals
  "I'm handling the error path").
* **Status helpers** (`info`, `error`, `die`) write to STDERR so CLI output
  pipelines stay clean. Use `info` for normal status, `error` for red, `die`
  to abort with a logged fatal.
* **`stream`** is for line-by-line consumption of long-running commands.
  Stdout and stderr are merged - if you need them separate, use `exec`.
* **POSIX only.** No Windows fallback paths in this module.

## Don't

* Don't use backticks or `Kernel.system("#{cmd}")` - they hide whether
  shell expansion happens and leak injection-prone interpolation.
* Don't use `shell: true` with user-supplied data unless you `shellescape`
  every interpolated value - and prefer argv mode in that case anyway.
* Don't reach for `Open3.*` directly in app code - `Lux.shell.exec` already
  wraps it with timeout, capture, and structured errors.
* Don't put `Lux.shell.info` calls in hot request paths - it's for CLI/boot
  status, not request logging (use `Lux.logger` for that).
* Don't `rescue` `Lux::Shell::Error` and silently drop it; either let it
  bubble or log `e.result.err` so the cause is recoverable.

## See also

* [`README.md`](./README.md) - human-facing API reference
* [`../logger/AGENTS.md`](../logger/AGENTS.md) - `Lux.logger`, used by `die`
