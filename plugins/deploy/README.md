# Lux deploy plugin

Docker-only deploy commands for Lux apps. The plugin builds Docker images locally, ships them to a host as a `docker save | gzip` archive, runs `docker compose up -d`, then generates a Caddy site block and reloads Caddy.

The runtime contract is just three things:

* Docker (Compose v2) on the host
* Caddy on the host with `/etc/caddy/sites/*.caddy` imports
* SSH with passwordless sudo

No Ruby, Bundler, Puma, Node, systemd, or Postgres setup is needed on the host. The image owns those.

## Commands

```sh
lux deploy:llm_prepare                # generate Dockerfile + compose + deploy.json via Claude CLI
lux deploy [PROFILE]                  # build (optional) + ship + compose up + caddy reload
lux deploy:doctor [PROFILE] [--app NAME]
lux deploy:build [PROFILE]            # build images locally, write tmp/deploy/<app>/images.tar.gz
lux deploy:test  [PROFILE] [--build]  # run archived images locally + health checks
lux deploy:staging [PROFILE]          # disposable PR/staging stack with project-local DB
lux deploy:remove  [PROFILE] [--purge] [--volumes]
lux deploy:ssh     [PROFILE]
lux deploy:logs    [PROFILE] [--service SVC] [--follow]
lux deploy:compose [PROFILE] -- <docker compose subcommand>
```

`PROFILE` defaults to `default` and is resolved from `config/deploy.json`.

## Local app layout

```text
config/
  deploy.json
  docker/
    Dockerfile
    compose.yml
    compose.staging.yml         # optional: project-local postgres for PR/staging
```

`config/docker/compose.yml` should resolve to the same definition locally and remotely, parameterised by environment variables the plugin writes:

* `LUX_RUNTIME_ENV_FILE` -- the `.env` to load into containers (`/home/<service_user>/lux-apps/<app>/shared/.env` remotely)
* `LUX_LOG_DIR`, `LUX_TMP_DIR` -- bind mount targets for log/tmp
* `LUX_SOURCE_DIR` -- defaults to the app root locally; remote value lets compose `build` succeed if invoked
* `<SVC>_IMAGE` -- image ref for each logical service in `services:`
* `<SVC>_PORT` -- resolved host port (loopback only)

## Config

Create `config/deploy.json` in your app:

```sh
cp plugins/deploy/templates/deploy.json.example config/deploy.json
```

Profiles inherit from `default`. A profile can set `extends` to inherit from another profile. CLI flags always win over JSON.

Supported placeholders in string values:

* `{{app}}`, `{{app_underscored}}`, `{{profile}}`, `{{image_tag}}`
* `{{host}}` -- docker bridge gateway (`172.17.0.1`); for containers reaching a service running on the host
* `{{config.a.b.c}}` -- reads from `Lux.config` on the caller side
* `{{env.KEY}}` -- the resolved env value (use only inside `env:` or `services.*` values that depend on it)

### Auto-derived (don't set these in deploy.json)

The plugin owns these by convention; the validator rejects them if you set them:

* `root` -- always `/home/<service_user>/lux-apps`
* `compose` -- always `["config/docker/compose.yml"]` (auto-appends `config/docker/compose.<profile>.yml` if it exists)
* `image_tag` -- `git rev-parse --short HEAD`, or `latest` if not in git; override per-call with `--image-tag`
* `images` -- one entry per service: `<app>-<svc>:<image_tag>`

### Defaults (override only if you really need to)

* `service_user` -- defaults to `deployer`. Override in deploy.json or via `--service-user` if you have a different system user owning app files.

### Env values

The `env:` block maps env keys to one of:

* `"literal"` -- string written verbatim
* `true` -- read from the caller's shell ENV at deploy time (required)
* `false` / `null` -- pass through if locally set, otherwise omitted
* `"$generate"` -- generate a stable 64-hex secret and store it in the remote `shared/.env` (reused on later deploys)

### Services

`services.*` maps logical service keys to:

* `compose_service` -- the matching service in compose.yml (defaults to the key)
* `host_port` -- explicit localhost port Caddy targets, or `null` to allocate from `port_range`
* `port_range` -- `[lo, hi]` used when `host_port` is null
* `container_port` -- documentation, not enforced
* `domains` -- array of domains this service serves on (first-class for socket/admin subdomains; wildcards like `*.example.com` are supported, see TLS below)
* `healthcheck` -- optional `{ path, expect_status, timeout }`

### TLS (wildcard / DNS-01)

A wildcard domain requires the ACME DNS-01 challenge, which means Caddy needs a DNS provider plugin compiled in. Configure it per profile:

```json
"tls": {
  "dns_provider": "cloudflare",
  "api_token_env": "CLOUDFLARE_API_TOKEN"
}
```

* `dns_provider` -- a supported `caddy-dns/<name>` plugin (currently `cloudflare`)
* `api_token_env` -- name of the env var holding the DNS API token; must be exported locally before running deploy

On deploy, the token is written to `/etc/caddy/caddy.env` (root:caddy 0640) and Caddy reads it via a systemd drop-in. The preflight check verifies the host's Caddy includes `dns.providers.<name>`; if it doesn't, it points you at an `xcaddy build` command. See `KNOWLEDGE.md` for the build recipe.

## Image transport

Default: archive. Build locally, save with `docker save | gzip`, scp to host, `docker load`. No registry credentials needed.

```sh
lux deploy:build                          # writes tmp/deploy/<app>/images.tar.gz
lux deploy:test                           # boots the archive locally and health-checks it
lux deploy                                # uploads + remote load + compose up + caddy reload
lux deploy --build                        # build the archive first if missing/stale
```

Optional: `lux deploy --transport registry` runs `docker compose pull` on the host instead of shipping the archive. Pushing the images to the registry is out of scope for v1 -- do it before invoking deploy.

## Host layout

Every app lives at `<root>/<app>/`. Root is fixed at `/home/<service_user>/lux-apps`. Path is fully derived.

```text
/home/deployer/lux-apps/
  myapp/
    manifest.json              # resolved deploy state, no secrets
    Caddyfile                  # generated; symlinked into /etc/caddy/sites/myapp.caddy
    config/
      docker/                  # rsync'd from local config/docker/
        compose.yml
        Dockerfile
        deploy.env             # compose --env-file; image refs, ports, paths (no secrets)
        images.tar.gz          # uploaded archive (when transport=archive)
    shared/
      .env                     # 0600; container runtime env (includes $generate secrets)
      log/
      tmp/
```

## SSH user vs service user

* **SSH user** (from `server`, e.g. `root@srv.example.com`) -- used only for the SSH connection. Needs passwordless sudo. `root` works.
* **Service user** (`service_user`, default `deployer`) -- owns the app tree on the host.

All file operations under `<root>/<app>/` are run as the service user. Docker itself runs as root (via group membership or socket access).

## Staging and PR deploys

`lux deploy:staging` deploys a disposable stack with its own DB:

* same Docker + Caddy machinery as production
* different `app` (e.g. `pr-123`) becomes the namespace, Compose project, Caddy file
* a `config/docker/compose.staging.yml` is auto-appended to the compose stack when the profile is `staging`
* compose config must declare a `db` service (unless `--allow-no-db`)
* `$generate` env values get a stable per-app password in `shared/.env`
* ports auto-allocate from `port_range`, then stay pinned in `manifest.json`

Destroy a PR deploy and its volume:

```sh
lux deploy:remove pr --app pr-123 --purge --volumes
```

## Doctor

`lux deploy:doctor` runs read-only checks against the host and each app's manifest:

* docker, docker compose v2, caddy, sudo, service user, root dir
* per-app: app dir, manifest, env file mode 0600, generated Caddyfile, symlink, compose config validity, ports respond

## Error format

Failures hard-stop with non-zero exit and a four-line operator message:

```text
ERROR: one-line summary
  expected: what should be true
  current:  what is actually true
  need:     what must change
  fix:      copy-pasteable command or path
```

Exit codes: `10` preflight, `20` source, `40` compose, `50` caddy, `60` health check, `99` unknown.

## Notes

* Concurrent deploys for the same `--app` are not locked.
* `--dry-run` prints the resolved command plan without remote changes.
* The plugin shells out to plain `docker compose` -- the printed commands can be copied verbatim.
