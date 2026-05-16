# Lux deploy plugin

SSH-based deploy commands for Lux apps. The plugin provisions a Lux app on a Linux host without Docker: source sync, bundle install, Postgres ensure, migrations, systemd units, Caddy reverse proxy, health checks, rollback, and teardown.

## Commands

```sh
lux deploy [PROFILE]
lux deploy:prepare [PROFILE] --with caddy,postgres
lux deploy:doctor [PROFILE]
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

## Example

```json
{
  "default": {
    "host": "deploy@srv.example.com",
    "path": "/var/www/{{app}}",
    "ruby": "3.4.7",
    "repo": "git@github.com:foo/bar.git",
    "db": {
      "user": "deploy",
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

The host must allow SSH key login for the deploy user and passwordless sudo.

```sh
ssh-copy-id deploy@srv.example.com
ssh deploy@srv.example.com 'echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/lux-deploy && sudo chmod 0440 /etc/sudoers.d/lux-deploy'
lux deploy:prepare --with caddy,postgres --host deploy@srv.example.com
lux deploy:doctor --host deploy@srv.example.com
```

For wildcard certificates, install a Caddy DNS provider build instead of the stock package:

```sh
lux deploy:prepare --with caddy-cloudflare,postgres --host deploy@srv.example.com
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

```text
/var/www/myapp/
  current -> releases/2026-05-16-09-23-22
  releases/
  shared/
    .env
    log/
    tmp/
```

Deploys create a fresh release dir, run bundle and migrations there, then atomically swap `current`. The plugin keeps the current release plus one previous release for rollback.

## Notes

* Postgres v1 uses local peer auth over the Unix socket. `db.user` should match the SSH deploy user that runs systemd services.
* Remote DB hosts and TCP/password auth are not supported in v1.
* Concurrent deploys for the same `--app` are not locked.
* `--dry-run` prints the resolved command plan without remote changes.
