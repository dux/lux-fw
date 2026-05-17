# Lux deploy plugin

Stupid-simple deploy via SSH + rsync. No Docker. No registry. No JSON.

The host is assumed to have:

* root SSH access
* `xcaddy` (caddy with whatever DNS plugins you need)
* `mise` installed for the `deployer` user
* Ruby 4.0.4 (or whatever mise pins) for `deployer`

Run `lux deploy:doctor` to verify / set up the rest.

## Commands

| command              | purpose |
| -------------------- | ------- |
| `lux deploy:up`      | deploy current branch |
| `lux deploy:redeploy`| destroy + deploy (fresh PORT) |
| `lux deploy:destroy` | stop service, unlink caddy/systemd, remove `~/lux-apps/<app>` |
| `lux deploy:doctor`  | check & prepare host (deployer user, dirs, caddy, ruby, bundler) |

Common flags:

* `--server HOST` -- override `config/deploy/server`
* `--dry-run`     -- print commands, no remote changes
* `--yes`         -- skip `deploy:destroy` confirmation
* `--no-fix`      -- `deploy:doctor` reports only, no auto-fix

## Project layout

Drop these in your app under `config/deploy/`:

```
config/deploy/
  .yaml                  # server: + domain: + any other shared keys
  .env                   # production env (used on master/main)
  .env.staging           # staging env (used on any other branch)
  caddy.conf             # caddy site file
  systemd.service        # systemd unit for the web server
  job.service            # optional: systemd unit for the job runner
```

Copy the bundled examples:

```sh
lux deploy:app:init
```

Every key in `.yaml` becomes an UPPERCASE `{{KEY}}` placeholder for every
template. The two required keys are `server` and `domain`; add anything
else you want to reuse across templates (e.g. `db_user`, `cdn`).

## Server layout

```
/home/deployer/lux-apps/<app>/
  release/                 # current code + bundle
    tmp -> ../shared/tmp
    log -> ../shared/log
    .env -> ../.env
  old-release/             # previous release, kept one cycle
  shared/
    tmp/                   # survives release swap
    log/                   # survives release swap
  .env                     # rendered, PORT lives here
  systemd.service          # rendered; linked into /etc/systemd/system/lux-web-<app>.service
  caddy.config             # rendered; linked into /etc/caddy/sites/<app>.caddy
  systemd.job.service      # optional; linked into /etc/systemd/system/lux-job-<app>.service
```

`<app>` is the first comma-separated value of `DOMAIN` from the rendered
`.env` (falls back to `.yaml`'s `domain:`; wildcards stripped: `*.foo` -> `foo`).

## Template substitution

`{{VAR}}` placeholders inside any template are replaced from:

1. **Git** (computed locally): `{{GIT_BRANCH}}`, `{{GIT_BRANCH_UNDERSCORE}}`
2. **`.yaml`**: every key uppercased -- `{{SERVER}}`, `{{DOMAIN}}`, etc.
3. **Server probe**: `{{PORT}}` -- reused from existing `.env`, or
   first free port in `3010..3990` step 10 (via `ss -tln`)
4. **Derived**: `{{DIR}}`, `{{RUBY}}`, `{{RUBY_DIR}}`
5. **The rendered `.env`** itself: every `KEY=VAL` line becomes a placeholder
   you can use in `caddy.conf` / `systemd.service` (e.g. `{{DOMAIN}}`)

Order: render `.env` first, parse it, then render the other templates with
the resulting env hash merged in.

## Deploy flow

```
1. read config/deploy/.yaml (server, domain, ...)
2. pick template:  master|main -> .env, anything else -> .env.staging
3. render .env -> derive <app> from DOMAIN (falls back to .yaml domain)
4. ensure remote dirs (deployer-owned)
5. allocate / reuse PORT
6. rsync code to new-release/
7. symlink tmp, log, .env into new-release/
8. upload rendered .env / systemd.service / caddy.config
9. bundle install (vendor/bundle, without development+test)
10. bundle exec lux e 1   (smoke test; abort + cleanup on failure)
11. atomic swap:  rm old-release; mv release old-release; mv new-release release
12. install symlinks under /etc/systemd/system and /etc/caddy/sites
13. systemctl daemon-reload + restart web + reload caddy
14. (if job.service present) restart lux-job-<app>
```

On any failure between step 6 and step 11, `release/` is untouched.

## Notes

* `lux deploy:destroy` prompts `type '<domain>' to confirm` unless `--yes`.
* `lux deploy:redeploy` always allocates a fresh PORT.
* Concurrent deploys for the same app are not locked. Don't.
