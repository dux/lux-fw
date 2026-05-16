# Lux deploy plugin

SSH-based deploy commands for Lux apps. The plugin provisions a Lux app on a Linux host without Docker: source sync, bundle install, Postgres ensure, migrations, systemd units, Caddy reverse proxy, health checks, rollback, and teardown.

## Commands

```sh
lux deploy [PROFILE]
lux deploy:prepare [PROFILE] --with caddy,postgres
lux deploy:doctor [PROFILE] [--app NAME]
lux deploy:reinstall [PROFILE] --app NAME
lux deploy:rollback [PROFILE]
lux deploy:remove [PROFILE] [--with-db]
lux deploy:list [PROFILE]
lux deploy:log [PROFILE]
lux deploy:tail [PROFILE] --app NAME
```

`PROFILE` defaults to `default` and is resolved from `config/deploy.json`.

## Config

Create `config/deploy.json` in your app. A starter template lives at:

```sh
cp plugins/deploy/templates/deploy.json.example config/deploy.json
```

Profiles inherit from `default`. A profile can set `extends` to inherit from another profile. CLI flags always win over JSON.

Supported placeholders in string values:

* `{{app}}`
* `{{app_underscored}}`
* `{{profile}}`
* `{{config.a.b.c}}`

`{{config.*}}` reads from `Lux.config` on the caller side.

## SSH user vs service user

Two identities exist on the host:

* **SSH user** (from `host`, e.g. `root@srv.example.com`) — used only for the SSH connection. Needs passwordless sudo. `root` works.
* **Service user** (`service_user`, default `deployer`) — owns the app tree, runs the systemd units, and is the Postgres peer-auth identity. Created by `lux deploy:prepare`.

`lux deploy:prepare` is idempotent and will:

* create the service user if missing
* copy the SSH user's `~/.ssh/authorized_keys` into the service user's home (merge + dedupe) so you can `ssh deployer@host` with the same key
* grant the service user passwordless sudo via `/etc/sudoers.d/lux-deploy-<user>`
* install mise + Ruby + bundler under the service user's home
* chown `/etc/caddy/sites`, `/var/log/lux-deploy`, and the app path to the service user

`bundle install`, migrations, and the running services all execute as the service user — even when you SSH as `root`. Postgres `db.user` defaults to `service_user` so peer auth lines up with the systemd identity.

## Example

```json
{
  "default": {
    "host": "root@srv.example.com",
    "service_user": "deployer",
    "ruby": "3.4.7",
    "repo": "git@github.com:foo/bar.git",
    "db": {
      "user": "deployer",
      "name": "{{app_underscored}}"
    },
    "domain": "foo.com",
    "port": null,
    "healthcheck": {
      "path": "/",
      "timeout": 30,
      "expect_status": [200, 201, 204, 301, 302]
    },
    "env": {
      "RACK_ENV": "production",
      "DATABASE_URL": "postgres:///{{app_underscored}}",
      "SECRET_KEY_BASE": true
    }
  },
  "pr": {
    "domain": "{{app}}.staging.foo.com"
  }
}
```

## One-time host preparation

The host must allow SSH key login for the SSH user and passwordless sudo. `root` works — the prepare step creates the service user for you.

```sh
ssh-copy-id root@srv.example.com
lux deploy:prepare --with caddy,postgres --host root@srv.example.com
lux deploy:doctor --host root@srv.example.com
```

After prepare, `ssh deployer@srv.example.com` works with the same key (prepare merged your authorized_keys into deployer's).

For wildcard certificates, install a Caddy DNS provider build instead of the stock package:

```sh
lux deploy:prepare --with caddy-cloudflare,postgres --host root@srv.example.com
```

Generic `caddy-<provider>` maps to `github.com/caddy-dns/<provider>`.

Provider credentials are not managed by this plugin. Add the provider's required environment or global Caddyfile configuration on the host.

## Deploy

From a working copy:

```sh
export SECRET_KEY_BASE=$(openssl rand -hex 64)
lux deploy --app myapp
```

From CI using a remote git clone:

```sh
lux deploy pr \
  --app pr-123 \
  --repo https://github.com/foo/bar.git \
  --branch pr-123-branch
```

Remove an ephemeral deploy:

```sh
lux deploy:remove pr --app pr-123 --with-db
```

## Error format

Failures hard-stop with non-zero exit and a four-line operator message:

```text
ERROR: one-line summary
  expected: what should be true
  current:  what is actually true
  need:     what must change
  fix:      copy-pasteable command or path
```

Exit codes: `10` preflight, `20` source, `30` database, `40` systemd, `50` caddy, `60` health check, `99` unknown.

## Layout on the host

Every app lives at `/home/<service_user>/lux-apps/<app>/`. The path is fully derived from `service_user` and `app` — no override. The filesystem itself is the app registry. Each app is self-describing: a `manifest.json` at the app root records the resolved deploy state so doctor, list, and reinstall don't need the local config.

```text
/home/deployer/lux-apps/
  myapp/
    manifest.json                       # resolved deploy state (no secrets)
    current -> releases/2026-05-16-09-23-22
    releases/
    shared/
      .env                              # 0600 deployer:deployer (resolved secrets)
      log/
      tmp/
  pr-123/
    manifest.json
    ...
```

Deploys create a fresh release dir, run bundle and migrations there, atomically swap `current`, then write `manifest.json` after the healthcheck passes. The plugin keeps the current release plus one previous release for rollback.

## Manifest

`<path>/manifest.json` records: app, service_user, ruby, host, domain, port, db (name + user, no secrets), systemd unit names, caddy site path, env schema (`required` / `optional` / `literal`, **never resolved values**), current release, deployed_at, ruby and bundle paths.

`lux deploy:doctor` reads every manifest under `/home/<service_user>/lux-apps/` and checks reality matches: systemd unit installed with `User=<service_user>`, services active, caddy site references the recorded port, `current` symlink is valid, bundle path exists, db role + database exist, `.env` is mode 0600. Pass `--app NAME` to scope to one app.

`lux deploy:reinstall --app NAME` reads the on-host manifest and re-renders the systemd unit + caddy site from the current templates, then reloads both. No release sync, no bundle, no db — handy when config drifts but the release tree is fine.

## Notes

* Postgres v1 uses local peer auth over the Unix socket. `db.user` defaults to `service_user`, which is also what systemd runs the app as.
* Remote DB hosts and TCP/password auth are not supported in v1.
* Concurrent deploys for the same `--app` are not locked.
* `--dry-run` prints the resolved command plan without remote changes.
