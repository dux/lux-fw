# Server deploy hammer

`lux deploy` / `lux deploy:remove` family of hammer commands that provisions a
Lux app onto a Linux server. No Docker. SSH-based, CI-friendly,
multi-tenant on a single host.

## Goal

* Single command spins up a Lux app on a remote server: source sync,
  bundle install, DB ensure, migrations, systemd units, Caddy reverse
  proxy with optional HTTP basic auth.
* Single command tears it all back down (for CI ephemeral PR deploys).
* JSON config with profile inheritance + CLI overrides so the same
  template drives prod, staging, and per-PR ephemeral environments.

## Commands at a glance

| Command                            | Purpose                                              |
|------------------------------------|------------------------------------------------------|
| `lux deploy [PROFILE]`             | deploy app to PROFILE (atomic, with health check)    |
| `lux deploy:prepare [PROFILE]`     | one-time server bootstrap (ruby, optional caddy/pg)  |
| `lux deploy:doctor [PROFILE]`      | read-only preflight diagnosis (no changes)           |
| `lux deploy:rollback [PROFILE]`    | revert to previous release (one step back)           |
| `lux deploy:remove [PROFILE]`      | tear down: stop units, remove caddy block, dir, DB   |
| `lux deploy:list`                  | list all deploys on a host, flag orphans             |
| `lux deploy:log`                   | tail the host-wide deploy event log                  |
| `lux deploy:tail`                  | tail an app's systemd journal (runtime stdout/err)   |

PROFILE is a key from `config/deploy.json` (`default`, `staging`,
`pr`, ...). Default profile is `default`.

Key flags (full list per command below):

* `--app NAME` - app identifier, namespaces dir/unit/DB/Caddy block
* `--host USER@HOST` - SSH target
* `--config PATH` - override default `config/deploy.json` lookup
* `--quiet` - CI-friendly output
* `--dry-run` - print resolved plan, don't execute

## Error handling

**Hard fail on any error.** No retries, no fallbacks, no auto-recovery,
no "best effort." If any step fails, the deploy aborts with a clear
error and a non-zero exit code. The system state is left as-is for
the operator to inspect or roll back manually.

Every error message uses the same four-line structure:

```
ERROR: <one-line summary>
  expected: <what should be true>
  current:  <what is actually true (with concrete identifiers - user, mode, host, version, etc.)>
  need:     <what the operator must change>
  fix:      <copy-pasteable command, config snippet, or path>
```

Concrete examples:

```
ERROR: cannot write /etc/caddy/sites/myapp.caddy
  expected: write access for user 'deploy' on /etc/caddy/sites/
  current:  user 'deploy', dir mode 0755 owner root:root (no write bit)
  need:     write permission for 'deploy' on /etc/caddy/sites/
  fix:      sudo chown -R deploy:deploy /etc/caddy/sites/
```

```
ERROR: passwordless sudo not configured on deploy@srv.example.com
  expected: `sudo -n true` exits 0 for user 'deploy'
  current:  `sudo -n true` exited 1, stderr "sudo: a password is required"
  need:     NOPASSWD sudo for user 'deploy'
  fix:      ssh deploy@srv.example.com 'echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/lux-deploy && sudo chmod 0440 /etc/sudoers.d/lux-deploy'
```

```
ERROR: required env var not set locally
  expected: SECRET_KEY_BASE present in caller's environment
  current:  SECRET_KEY_BASE unset
  need:     export SECRET_KEY_BASE before running deploy (declared as `true` in deploy.json env block)
  fix:      export SECRET_KEY_BASE=$(openssl rand -hex 64)
```

```
ERROR: caddy not running on deploy@srv.example.com
  expected: systemctl is-active caddy = 'active'
  current:  systemctl is-active caddy = 'inactive'
  need:     caddy installed and running on the app host
  fix:      lux deploy:prepare --with caddy --host deploy@srv.example.com
```

Rules:

* No emoji, no ANSI in machine output (`--quiet` mode strips colour
  too). Interactive mode may colourize the `ERROR:` line in red.
* `current:` must include concrete identifiers (actual user, file mode,
  exit code, stderr snippet) — not abstract descriptions. The
  operator should never have to re-run a diagnostic to learn what
  failed.
* `fix:` must be a single copy-pasteable command or a path to edit.
  No prose; no "see README." If the fix is multi-step, link to a
  named section of the README.
* Errors flow to stderr. Exit code is non-zero (use specific codes
  per category: 10=preflight, 20=source, 30=db, 40=systemd, 50=caddy,
  60=healthcheck, 99=unknown).

## Stack

* **Reverse proxy**: Caddy
  * Native glob domain matching: `foo.com, *.foo.com {}` and
    `*.staging.foo.com {}` are first-class.
  * Auto-HTTPS via Let's Encrypt. Wildcards require DNS-01; user
    configures DNS provider plugin (e.g. `caddy-dns/cloudflare`) on
    the host once. Plan documents this; does not automate it.
  * Reload is graceful. Config lives one-file-per-app under
    `/etc/caddy/sites/{app}.caddy`, included from main Caddyfile.
* **App + jobs**: systemd, generated **by the deploy plugin itself**.
  Writes `lux-web-{app}.service` + `lux-job-{app}.service` with
  `WorkingDirectory={path}/current` (the symlinked release dir, see
  "Release layout" below). Unit templates live inside the plugin at
  `plugins/deploy/templates/`; no external command dependency.
* **DB**: Postgres.
  * Default: co-located on app server, provision via `sudo -u postgres
    psql`. Deploy user must have passwordless `sudo` to the `postgres`
    OS user; preflight verifies this and aborts early if missing (see
    Preflight section).
  * Same-zone remote DB host: SSH to the DB host and run the same
    `sudo -u postgres psql` there. Driven by `db.host` in config or
    `--db-host` CLI flag.
  * Idempotent create: `SELECT 1 FROM pg_database WHERE datname = ...`
    then `CREATE DATABASE ... OWNER {db.user}` if missing.
* **Transport**: SSH from caller (laptop or CI). No agent on server.
* **Source sync**: flag-driven, mutually exclusive:
  * `--branch BRANCH` -> `git clone --branch BRANCH --depth=1` on server.
    Requires `--repo URL` (or `repo` in config). Passing `--src`
    together with `--branch` is a hard error
    (`"--branch and --src are mutually exclusive"`), surfaced during
    argument parsing before any remote contact.
  * `--src PATH` -> rsync from local PATH to remote.
  * Neither -> rsync from cwd (default for laptop deploys).

## Config: `config/deploy.json`

Discovery: starting at cwd, walk up the directory tree looking for
`Hammerfile` (the app-root marker). The deploy config is then
`{app_root}/config/deploy.json` (overridable with `--config PATH`).
`lux deploy` works from any subdirectory of the app. Bail with
`"no Hammerfile found in cwd or parents; not inside a Lux app"` if
none is found.

Example `config/deploy.json` with `default` and two derived profiles:

```json
{
  "default": {
    "host":   "deploy@srv.example.com",
    "path":   "/var/www/{{app}}",
    "ruby":   "3.4.7",
    "repo":   "git@github.com:foo/bar.git",
    "db": {
      "host": "localhost",
      "user": "deploy",
      "name": "{{app}}"
    },
    "domain":     "foo.com",
    "basic_auth": null,
    "port":       null,
    "healthcheck": {
      "path":          "/",
      "timeout":       30,
      "expect_status": [200, 201, 204, 301, 302]
    },
    "env": {
      "RACK_ENV":        "production",
      "DATABASE_URL":    "postgres:///{{app}}",
      "SECRET_KEY_BASE": true,
      "STRIPE_KEY":      true,
      "DEBUG":           false
    }
  },
  "staging": {
    "domain": "*.staging.foo.com",
    "env": {
      "RACK_ENV": "staging",
      "DEBUG":    "1"
    }
  },
  "pr": {
    "extends": "staging",
    "domain":  "{{app}}.staging.foo.com"
  }
}
```

Resolution order:

1. `default` block (always the base, implicit)
2. selected env block deep-merged on top of `default`. Implicit
   `extends: default` - no need to declare it. Override by setting
   `extends: <other-env>` (chain still terminates at `default`). The
   `default` block itself does not extend anything.
3. CLI flags merged last (highest priority)
4. Interpolation pass applied to every string in the resolved tree.

### Interpolation

`{{...}}` placeholders in string values are expanded recursively after
config resolution. Supported namespaces:

| placeholder            | source                                                                    |
|------------------------|---------------------------------------------------------------------------|
| `{{app}}`             | the `--app` flag (or default from cwd dirname)                            |
| `{{profile}}`         | the selected profile name (`default`, `staging`, `pr`, ...)               |
| `{{config.a.b.c}}`     | `Lux.config.dig('a', 'b', 'c')` on the caller side                        |

`Lux.config` requires the app's `config/env` to be loaded — the deploy
hammer commands declare `needs :env` so it's available before
resolution. Unresolved placeholders are a hard error
(`"unresolved {{config.foo.bar}} in deploy.json"`), not a silent empty
string.

Example: avoid restating the prod DB host in two places.

```json
{
  "default": {
    "host":   "deploy@{{config.deploy.host}}",
    "domain": "{{config.app.domain}}",
    "db":     { "host": "{{config.db.host}}", "name": "{{app}}" }
  }
}
```

`port` left null -> auto-allocate. Deterministic by `--app`: hash
`app` into 3000-3999, increment on collision with an existing
`/etc/caddy/sites/*.caddy` block. Same app re-deploys to the same
port (idempotent), concurrent CI deploys with different apps cannot
collide.

### `db` vs `env.DATABASE_URL`

These are intentionally separate:

* `db:` block is consumed by the deploy plugin to provision the role
  + database (`CREATE ROLE`, `CREATE DATABASE`). Deploy never sets
  `DATABASE_URL` on the app.
* `env.DATABASE_URL` is what the running app reads. It must be set
  by the operator; deploy does not derive it from `db:`.

Keep them in sync manually, or interpolate (e.g.
`"DATABASE_URL": "postgres:///{{app}}"` with peer auth picking up
`db.user`). v1 does not auto-generate `DATABASE_URL` to avoid hiding
the contract.

### DB authentication model

v1 uses **Postgres peer authentication over Unix socket**. No
passwords, no `pg_hba.conf` edits.

* The role created by deploy (`db.user`) **must match the OS user the
  app runs as**. The plugin's systemd unit templates render `User=`
  to the deploy SSH user (e.g. `deploy@srv` -> `User=deploy`). So
  `db.user` defaults to that same name (`deploy` in the example).
* App connects via Unix socket with no host: `DATABASE_URL=postgres:///{{app}}`.
  Postgres' default `pg_hba.conf` includes `local all all peer`, which
  trusts the OS user as the postgres role of the same name.
* Deploy creates the role with: `CREATE ROLE {db.user} LOGIN` (no
  password). The role owns its DB.

Constraint: if you set `db.user` to anything other than the deploy
OS user, peer auth breaks and the app can't connect. The plan does
not support TCP/password auth in v1. Future v2 could add it for
remote DB hosts or multi-tenant boxes.

### `env` block

Hash, deep-merged per key across `default -> env -> CLI`. Children
override individual keys without restating the rest. Resolved values
are written to a remote `.env` file at `{path}/shared/.env` before
bundle install (so migrations + boot see them); each release symlinks
`releases/{ts}/.env -> ../../shared/.env`.

Value semantics:

| value         | meaning                                                                                  |
|---------------|------------------------------------------------------------------------------------------|
| `"literal"`   | string, written as-is to remote `.env`                                                   |
| `true`        | required. Pulled from caller's ENV at deploy time. Fails if missing locally. Written to remote `.env`. |
| `false`       | optional. Pulled from caller's ENV if set; if unset locally, skipped (server retains prior value).     |

CLI overrides:

* `--env KEY=VAL`     literal value
* `--env KEY`         force-pull `KEY` from caller's ENV (equivalent to `true` in config)

All interpolations (`{{app}}`, `{{profile}}`, `{{config.*}}`) apply to
env string values too.

## Release layout

Capistrano-style atomic deploys:

```
{path}/
  current -> releases/2026-05-16-09-23-22   # symlink, atomic swap
  releases/
    2026-05-16-09-23-22/                    # newest, just deployed
      ... app source + vendor/bundle ...
    2026-05-15-14-10-05/                    # previous, kept for rollback
  shared/
    .env                                    # symlinked into each release
    log/
    tmp/
```

* Each deploy writes a fresh `releases/{ts}` dir (timestamp =
  `YYYY-MM-DD-HH-MM-SS` UTC).
* `bundle install` and `lux db:am` run inside the new release dir,
  before the symlink swap. Failure leaves `current` pointing at the
  old release; nothing breaks.
* After successful prep, `ln -sfn releases/{ts} current` is a single
  atomic syscall.
* `systemctl reload-or-restart` only after the swap succeeds.
* `shared/.env` is symlinked into each release as `releases/{ts}/.env`
  so secrets persist across deploys. `shared/log` and `shared/tmp`
  symlinked likewise.
* Pruning: keep `current` + 1 previous (so rollback works). Older
  releases deleted at the end of each successful deploy.

## Deploy log

Single host-wide log at `/var/log/lux-deploy/deploy.log`. Append-only,
one line per deploy event (start, step, success, fail, rollback).
Format:

```
2026-05-16T09:23:22Z [myapp]     deploy start  release=2026-05-16-09-23-22 ref=git:main@abc1234
2026-05-16T09:23:25Z [myapp]     bundle install ok
2026-05-16T09:23:31Z [myapp]     migrate ok
2026-05-16T09:23:32Z [myapp]     swap current -> releases/2026-05-16-09-23-22
2026-05-16T09:23:33Z [myapp]     reload web ok
2026-05-16T09:23:34Z [myapp]     reload job ok
2026-05-16T09:23:34Z [myapp]     deploy ok    duration=12s
2026-05-16T10:01:05Z [pr-123]    deploy start  release=...
```

`[app]` is the app's `--app` (defaults to folder basename, not full
path). Filter with `grep '\[myapp\]' /var/log/lux-deploy/deploy.log`.

`lux deploy:log [--app NAME] [--tail N]` is a thin wrapper that
greps + tails this file remotely.

`/var/log/lux-deploy/` is created during `deploy:prepare`, owned by
the deploy user (so no sudo needed to append). Standard logrotate
handles rotation (`/etc/logrotate.d/lux-deploy` written by prepare).

## Commands

### `lux deploy:prepare [PROFILE] [opts]`

One-time server bootstrap. Idempotent: safe to re-run.

Flags: `--host`, `--ruby VERSION` (overrides config `ruby`), `--with caddy,postgres`.

Steps on remote (over SSH, with sudo as needed):

1. Detect distro (apt/dnf/pacman).
2. Install build deps (`build-essential`, `libssl-dev`, `libreadline-dev`,
   `zlib1g-dev`, `libyaml-dev`, `libffi-dev`, `git`, `curl`, `rsync`).
3. Install rbenv + ruby-build for the deploy user (skip if present).
4. `rbenv install -s {ruby}` then `rbenv global {ruby}` (where `{ruby}` is the resolved `ruby` field from deploy.json).
5. `gem install bundler --no-document` (skip if present).
6. Optional via `--with` (comma-separated list):
   * `caddy`              install default caddy package, enable + start.
   * `caddy-cloudflare`   build caddy with the cloudflare DNS plugin
     via `xcaddy build --with github.com/caddy-dns/cloudflare`,
     install binary to `/usr/local/bin/caddy`, then enable + start.
     Required for wildcard certs (`*.foo.com`) using Cloudflare DNS.
   * `caddy-route53`      same, with `caddy-dns/route53`.
   * `caddy-digitalocean` same, with `caddy-dns/digitalocean`.
   * `caddy-*`            generic pattern: any `caddy-<provider>` maps to
     `github.com/caddy-dns/<provider>`. Other providers added by name.
   * `postgres` -> install postgresql, enable + start. No role/auth
     setup needed - deploy uses `sudo -u postgres psql` and creates
     roles on demand.

   Note: `caddy` and any `caddy-*` are mutually exclusive within a
   single `prepare` run. Re-running with a different variant
   reinstalls.
7. Verify passwordless sudo (`sudo -n true`) and `sudo -u postgres
   psql -c 'select 1'` if postgres installed. Print a remediation
   sudoers snippet and abort if either fails.
8. Ensure `/etc/caddy/sites/` exists and main Caddyfile imports it.
9. Ensure `/var/log/lux-deploy/` exists and is owned by the deploy
   user: `sudo mkdir -p /var/log/lux-deploy && sudo chown
   deploy:deploy /var/log/lux-deploy && sudo chmod 0755
   /var/log/lux-deploy`. Subsequent deploy events append without
   sudo.
10. Write `/etc/logrotate.d/lux-deploy`:
    ```
    /var/log/lux-deploy/deploy.log {
        weekly
        rotate 8
        compress
        delaycompress
        notifempty
        missingok
        copytruncate
    }
    ```
    Idempotent: skip rewrite if file content matches.
11. Print versions of installed components.

Ruby version comes from `ruby` field in the resolved config (same
resolution as `lux deploy`). Required field for `prepare`; deploy
itself only uses it to sanity-check that `rbenv local` matches.

**Scope: app host only.** `deploy:prepare` always targets `--host`
(the app host). If `db.host` differs from the app host, the DB box
is **not** bootstrapped by this command. README documents the manual
setup for a separate DB host: install postgresql, enable + start,
ensure passwordless sudo for the deploy user, ensure `sudo -u postgres
psql` works. This keeps `prepare` single-purpose and the
multi-host scenario fully explicit.

### `lux deploy [PROFILE] [opts]`

Flags:

* `--app NAME`             logical app identifier; drives path, unit, DB, Caddy block. Defaults to `File.basename(Dir.pwd)` in rsync-from-cwd mode. **Required when `--branch` is set** (no cwd to derive from); deploy aborts early with `"--branch requires --app"`.
* `--host USER@HOST`       SSH target
* `--path PATH`            remote app dir (overrides `path` in config)
* `--src PATH`             local rsync source (default cwd; ignored when `--branch` is set)
* `--domain DOMAIN[,...]`  one or more domains for Caddy block
* `--db-url URL`           full postgres:// URL (skips `--db-host` / `--db-name`)
* `--db-host HOST`         DB host (SSH there if not localhost)
* `--db-name NAME`         DB name
* `--basic-auth user:pass` enables HTTP basicauth in the Caddy block
* `--port N`               app port (auto-allocated if absent)
* `--repo URL`             git repo URL (with `--branch`)
* `--branch BRANCH`        switches source mode to git clone
* `--dry-run`              print resolved config + planned remote commands, do not execute
* `--quiet`                suppress per-step progress; print only errors + the final one-line summary (`deploy ok myapp release=2026-05-16-09-23-22 duration=12s`). Stderr still receives error detail. Exit codes unchanged. CI-friendly.
* `--config PATH`          override the default `config/deploy.json` lookup. Useful for monorepos or per-CI-job configs.

Steps:

1. Resolve config: load `config/deploy.json` (or `--config PATH`),
   apply `extends` chain, overlay CLI flags, then run interpolation
   pass (`{{app}}`, `{{profile}}`, `{{config.*}}`). Requires
   `needs :env` so `Lux.config` is available.
2. SSH + sudo preflight:
   * host reachable over SSH
   * ruby + bundler present
   * `path` writable
   * caddy + postgres running (`systemctl is-active`)
   * **passwordless sudo works**: `ssh host sudo -n true` must succeed.
     Same check against `db.host` if it differs from app host.
   * `sudo -u postgres psql -c 'select 1'` works on the DB host.

   Any failure aborts before any state changes. Each check uses the
   standard four-line error format (see "Error handling" section).
   Categories with their exit codes:

   * SSH unreachable                  (exit 10)
   * ruby / bundler missing on host   (exit 10)
   * caddy not active                 (exit 10)
   * postgres not active              (exit 10)
   * passwordless sudo missing        (exit 10)
   * `sudo -u postgres psql` fails    (exit 10)
   * required env var unset locally   (exit 10)
   * target path not writable         (exit 10)
3. Compute release timestamp `ts = YYYY-MM-DD-HH-MM-SS` (UTC). New
   release dir is `{path}/releases/{ts}`. Append `deploy start` to
   `/var/log/lux-deploy/deploy.log` with `[{app}]` tag.
4. Source sync into the new release dir:
   * `--branch` set -> `git clone --branch B --depth=1 REPO {path}/releases/{ts}`
   * else -> `rsync -az --delete --exclude tmp --exclude log {src}/ host:{path}/releases/{ts}/`
5. Resolve `env` block: read caller's ENV for required (`true`) and
   optional (`false`) keys. Bail with `"required env KEY missing"`
   if any `true` key is unset locally. Write `{path}/shared/.env`
   with the resolved values (only update keys provided; preserve
   others) and symlink `{path}/releases/{ts}/.env -> ../../shared/.env`.
   Same pattern for `log` and `tmp` dirs.
6. `ssh host "cd {path}/releases/{ts} && bundle install --deployment --without development test"`.
7. DB ensure (all psql runs as `sudo -u postgres`):
   * Parse `db.host`. If `localhost` or same as app host, run psql on the app host.
   * Else SSH to `db.host` and run psql there.
   * Idempotent: skip if `SELECT 1 FROM pg_database WHERE datname='X'` returns 1.
   * Role `db.user` ensured: `CREATE ROLE {user} LOGIN` if missing.
   * `CREATE DATABASE {app} OWNER {user}` if missing.
8. `ssh host "cd {path}/releases/{ts} && bundle exec lux db:am"`.
9. Generate + install systemd units. The deploy plugin renders unit
   files from internal templates (see `lib/lux_deploy_systemd.rb`),
   then installs them. Two-phase to avoid sudo PATH scrubbing:
   1. Render `lux-web-{app}.service` and `lux-job-{app}.service` to a
      user-writable temp dir locally on the caller side (no SSH
      needed), substituting `{app}`, `{user}` (the deploy SSH user),
      `{working_dir}` (`{path}/current`), `{port}`, and any env-file
      directive.
   2. scp the rendered files to `{path}/releases/{ts}/.sysd/`.
   3. Install: `ssh host "sudo install -m 0644
      {path}/releases/{ts}/.sysd/lux-*.service /etc/systemd/system/
      && sudo systemctl daemon-reload"`.

   Idempotent: compare rendered content to the currently-installed
   `/etc/systemd/system/lux-{web,job}-{app}.service`; skip the
   install + daemon-reload if unchanged.
10. **Atomic swap**: `ssh host "ln -sfn releases/{ts} {path}/current"`
    (single syscall, no intermediate state).
11. `ssh host "sudo systemctl reload-or-restart lux-web-{app} lux-job-{app}"`. (`daemon-reload` already happened in step 9.2 if units changed.)
12. Health check: poll `ssh host curl -fsS -o /dev/null -w '%{http_code}' http://localhost:{port}{healthcheck.path}`
    every 1s for up to `healthcheck.timeout` seconds. Pass if the
    response status is in `healthcheck.expect_status` (defaults
    `[200, 201, 204, 301, 302]`). On timeout or persistent
    non-matching status: hard fail (exit 60). Log the failure to the
    deploy log with the last HTTP status + curl stderr. `current`
    symlink is left pointing at the new (broken) release - operator
    inspects, then runs `lux deploy:rollback --app X` to restore the
    previous release. No auto-rollback.

    Error example:
    ```
    ERROR: deploy health check failed on lux-web-myapp
      expected: GET http://localhost:3142/ returns 2xx within 30s
      current:  GET http://localhost:3142/ returned 502 for 30s (last stderr: "upstream connect error")
      need:     app boots cleanly on the new release
      fix:      ssh deploy@srv.example.com sudo journalctl -u lux-web-myapp -n 100 --no-pager   # diagnose, then: lux deploy:rollback --app myapp
    ```
13. Write `/etc/caddy/sites/{app}.caddy`:
    ```
    {domains} {
        {basicauth_block}
        reverse_proxy localhost:{port}
    }
    ```
    Ensure main Caddyfile has `import /etc/caddy/sites/*.caddy`.
14. `sudo systemctl reload caddy`.
15. Prune releases: keep `current` + 1 previous, delete the rest.
16. Append `deploy ok` + duration to the deploy log.
17. Print summary: domain(s), port, DB, unit names, release timestamp.

Failure behaviour:

* Before the atomic swap (steps 3-9): `current` still points at the
  previous working release, app keeps running on old code. The failed
  `releases/{ts}` dir is left in place for inspection; the next
  successful deploy's prune step removes it. Hard fail with the
  standard error format, exit code per category.
* During or after the atomic swap (steps 10+): `current` now points
  at the new release. If a later step fails (including the health
  check), the deploy still hard-fails, but the symlink is **not**
  rolled back automatically. Operator inspects, then runs
  `lux deploy:rollback --app X` to restore.

All failures append a `deploy fail` line with the failing step and
exit code to the host-wide deploy log.

### `lux deploy:remove [PROFILE] [opts]`

Flags: `--app`, `--host`, `--with-db` (default false), `--config PATH`.

Steps:

1. Resolve config.
2. Append `remove start` to deploy log with `[{app}]` tag.
3. `ssh host "sudo systemctl stop lux-web-{app} lux-job-{app}"`
4. `ssh host "sudo systemctl disable lux-web-{app} lux-job-{app}"`
5. `ssh host "sudo rm -f /etc/systemd/system/lux-web-{app}.service /etc/systemd/system/lux-job-{app}.service && sudo systemctl daemon-reload"`.
6. Delete `/etc/caddy/sites/{app}.caddy`, reload caddy.
7. `ssh host "rm -rf {path}"` (removes `current` symlink, all
   release dirs, `shared/`).
8. If `--with-db`: drop DB (`DROP DATABASE IF EXISTS ...`).
9. Append `remove ok` to deploy log. Print summary.

### `lux deploy:rollback [PROFILE] [opts]`

Flags: `--app`, `--host`, `--config PATH`.

Re-points `{path}/current` at the second-newest release dir, then
`reload-or-restart` the units. One step back only (we keep exactly
one previous release). Logs the rollback to the deploy log.

Errors out if only one release exists (nothing to roll back to).

### `lux deploy:doctor [PROFILE] [opts]`

Flags: `--host`, `--config PATH`.

Read-only diagnosis. Runs the same preflight checks that `lux deploy`
does (SSH, sudo, ruby, bundler, caddy, postgres, sudo-as-postgres,
target paths, deploy log dir, /etc/caddy/sites/) but **never changes
state**. Prints a status table; each failing check uses the standard
four-line error format with its remediation `fix:` line.

Example output:

```
Host: deploy@srv.example.com

  ssh                           ok
  ruby (3.4.7)                  ok
  bundler                       ok
  passwordless sudo             ok
  caddy active                  FAIL
  postgres active               ok
  sudo -u postgres psql         ok
  /etc/caddy/sites writable     ok
  /var/log/lux-deploy writable  ok

ERROR: caddy not running on deploy@srv.example.com
  expected: systemctl is-active caddy = 'active'
  current:  systemctl is-active caddy = 'inactive'
  need:     caddy installed and running on the app host
  fix:      lux deploy:prepare --with caddy --host deploy@srv.example.com

1 check failed.
```

Exit 0 on all-ok, exit 10 (preflight category) on any failure. Useful
for first-time setup verification and CI smoke tests.

### `lux deploy:log [opts]`

Flags: `--app NAME` (filter), `--tail N` (default 50), `--follow`,
`--host`.

Thin wrapper around `ssh host "grep '\[{app}\]' /var/log/lux-deploy/deploy.log | tail -N"`.
With `--follow`, runs `tail -F` and pipes through the grep filter.

Distinct from `deploy:tail` below (which tails the app's runtime
journal). `deploy:log` is the deploy event log (start/ok/fail).

### `lux deploy:tail [opts]`

Flags: `--app NAME` (required), `--lines N` (default 100), `--follow`,
`--host`.

Tail the systemd journal for the app's web + job units:

```
ssh host "sudo journalctl -u lux-web-{app} -u lux-job-{app} -n {lines}"
```

`--follow` adds `-f` to journalctl.

### `lux deploy:list [opts]`

Flags: `--host`.

Cross-references three sources:

* `/etc/caddy/sites/*.caddy` - one block per deploy
* `systemctl list-units 'lux-web-*.service' 'lux-job-*.service'` - units
* `{path}/current` symlinks under `/var/www` (best-effort, via
  `find /var/www -maxdepth 2 -name current -type l`). v1 assumes
  `/var/www` as the deploy root; non-default roots are picked up
  only through caddy + systemd sources.

Output one row per `--app`, union of all sources. Columns:

```
NAME       DOMAIN                        PORT   WEB        JOB        RELEASE
myapp      foo.com, *.foo.com            3142   running    running    2026-05-16-09-23-22
pr-123     pr-123.staging.foo.com        3287   running    running    2026-05-16-10-01-05
stale-a    -                             -      running    -          (orphan: no caddy block)
stale-b    example.com                   3500   -          -          (orphan: no service)
```

Orphan rows highlighted (different colour or `(orphan: ...)` suffix)
so partial-failed deploys / abandoned configs are visible. Operator
can clean them up with targeted `lux deploy:remove --app X`.

## CI flow

```sh
# On PR open
lux deploy pr \
  --app pr-123 \
  --repo https://github.com/foo/bar \
  --branch pr-123-branch

# On PR close
lux deploy:remove pr --app pr-123 --with-db
```

`--app` namespaces everything (dir, units, DB, Caddy block) so a
single VPS hosts many concurrent PR deploys.

## Prerequisites (one-time, documented in README)

The plugin does not auto-configure the server's auth model. README
walks through these; preflight verifies and aborts with a specific
remediation message on failure.

* **SSH key access** for the deploy user. `ssh-copy-id deploy@host`.
* **Known host key**. First-time hosts: `ssh-keygen -F host` or use
  `ssh-keyscan host >> ~/.ssh/known_hosts` ahead of time so
  `StrictHostKeyChecking` doesn't prompt.
* **Passwordless sudo** for the deploy user. Drop a file at
  `/etc/sudoers.d/lux-deploy`:
  ```
  deploy ALL=(ALL) NOPASSWD:ALL
  ```
  Mode 0440, validate with `visudo -c`.
* **Agent forwarding** (`ssh -A`) when deploying with `--branch` from
  a private git repo - the remote `git clone` uses the operator's
  local SSH agent. CI runners: load the deploy key into ssh-agent
  before `lux deploy`.
* **DB host sudo** if `db.host` differs from app host: same
  passwordless-sudo requirement on the DB box.

Preflight (see deploy step 2) checks each of these and aborts with
the matching one-liner remediation if any fail. No partial state.

## Systemd unit templates

The deploy plugin renders its own systemd units. Templates live in
`plugins/deploy/templates/` and are filled in by
`lib/lux_deploy_systemd.rb`.

`templates/lux-web.service.erb`:

```
[Unit]
Description=Lux web - <%= app %>
After=network.target

[Service]
Type=simple
User=<%= user %>
WorkingDirectory=<%= working_dir %>
EnvironmentFile=<%= working_dir %>/.env
ExecStart=<%= bundle %> exec lux server -e production -p <%= port %>
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

`templates/lux-job.service.erb`:

```
[Unit]
Description=Lux job runner - <%= app %>
After=network.target

[Service]
Type=simple
User=<%= user %>
WorkingDirectory=<%= working_dir %>
EnvironmentFile=<%= working_dir %>/.env
ExecStart=<%= bundle %> exec lux job_runner:start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Substitutions resolved at render time on the caller side:

* `app`         = the `--app` value
* `user`        = the SSH user from `host:` (`deploy@srv -> deploy`)
* `working_dir` = `{path}/current` (release symlink)
* `bundle`     = absolute path to `bundle` on the remote (looked up
  during preflight via `ssh host 'which bundle'`)
* `port`        = the resolved port

Compared to the installed copy on each deploy; reinstalled only on
content diff (see deploy step 9).

## Plugin layout

Everything lives under `plugins/deploy/`. No code under `bin/cli/`,
`lib/lux/`, or `doc/`. Follows the existing plugin convention
(`plugins/job_runner/`, `plugins/db/`).

```
plugins/deploy/
  loader.rb                  plugin entry; requires lib/* on demand
  deploy_hammer.rb           all hammer commands, wrapped in `namespace :deploy`
  README.md                  end-user docs (Caddy DNS-plugin setup, CI examples)
  lib/
    lux_deploy.rb            top-level orchestrator (LuxDeploy module)
    lux_deploy_config.rb     JSON loader, default-extends, interpolation ({{app}}, {{profile}}, {{config.*}}), CLI overlay
    lux_deploy_ssh.rb        SSH / rsync wrappers (`ssh`, `scp`, `rsync_to`)
    lux_deploy_caddy.rb      site block writer + reload
    lux_deploy_postgres.rb   ensure / drop DB (local + remote-via-ssh)
    lux_deploy_systemd.rb    render units from templates, install + uninstall, daemon-reload
    lux_deploy_prepare.rb    one-time server bootstrap (rbenv + ruby, optional caddy/postgres)
    lux_deploy_port.rb       auto-allocate free port
    lux_deploy_release.rb    release dir create + atomic symlink swap + prune
    lux_deploy_log.rb        append + tail the host-wide deploy log
  templates/
    deploy.json.example         starter config dropped into app on first run
    lux-web.service.erb         systemd unit template (web)
    lux-job.service.erb         systemd unit template (job runner)
    logrotate.conf.erb          /etc/logrotate.d/lux-deploy template
```

Command namespace stays `deploy:*` (e.g. `lux deploy:prepare`,
`lux deploy:list`). The bare `lux deploy` is exposed at root for
ergonomics by a top-level `define :deploy` inside the same
`deploy_hammer.rb`, delegating to the namespace implementation. All
other commands (`remove`, `prepare`, `doctor`, `rollback`, `list`,
`log`, `tail`) stay namespaced - no bare aliases.

Auto-discovery: `Hammerfile`'s `load auto: true` already scans
`plugins/**/*_hammer.rb`, so no wiring needed beyond dropping the
files in place.

## Open items / future

* Asset precompile hook (call `lux assets:auto` if present after bundle).
* Expose `job_runner:web` (port 3001, basicauth) through Caddy at e.g. `jobs.foo.com`. v1: operator reaches it via SSH tunnel or hand-rolled Caddy block. v2 candidate.
* Cert provider auth (Cloudflare API token, AWS credentials, etc.) -
  user writes them into `/etc/caddy/Caddyfile` global block or env
  vars on the caddy service. README documents the snippet per
  provider; deploy plugin doesn't manage these secrets. v1: document.

## Non-goals

* Deploy locking. Concurrent `lux deploy` runs against the same
  `--app` are not prevented; operator/CI is expected to serialize.
  Release timestamps are second-resolution, so two deploys within the
  same second could collide on `releases/{ts}` - document as a known
  edge case.
* Docker.
* Kubernetes.
* Multi-region / load-balanced deploys.
* Blue-green or zero-downtime swap (v1 is restart-based; <1s downtime).
* Windows servers.
