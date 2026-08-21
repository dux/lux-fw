# vibe - vibe coding harness for lux apps

One browser page next to your running app: a chat with an agent that edits the code,
a live preview of the app, the changed files with diffs, and git buttons (commit with a
generated or typed message, push, pull, merge main in, discard). Plus a restart button
and per-message revert. Everything runs in docker compose next to the app itself.

```
browser :4000 ──► vibe container ──┬── Sinatra harness (lux docker:vibe:server)  page + /api + /oc proxy
                                  └── opencode serve :4096 (agent, OpenRouter model)
                        │ same ./ checkout, same ./local/bundle, docker socket for hard restart
browser :3000 ──► app container (your lux app, puma + rollup watch)  ◄── preview iframe
```

* The agent is `opencode serve` (headless) talking to OpenRouter with `OPENROUTER_API_KEY`
  and the model in `VIBE_MODEL` (opencode id, `provider/model`).
* The checkout is pinned to the git branch `vibe` (`VIBE_BRANCH`). `lux docker:vibe:run`
  switches to it (creates it from `main` when missing) and refuses with a dirty tree.
  `main -> vibe` merge is a button; `vibe -> main` is not - that is a review you do by hand.
* Revert: every user message has "revert to here" (opencode restores the files and hides
  the later messages, Unrevert puts them back); Git tab has "discard all" (`reset --hard` +
  `clean -fd`) and Files has per-file discard.
* Restart: soft = `touch tmp/restart.txt` (puma `tmp_restart`, about a second, for
  ruby/haml/routes); hard = `docker restart` of the app container over the mounted socket
  (Gemfile / package.json). JS/CSS are rebuilt by the app's rollup watcher as usual.

## Setup in an app

All docker files live in `config/docker/` and compose is run with
`--project-directory <app root>`, so paths inside the compose files are relative to the
app root. The app's own local stack is expected at `config/docker/docker-compose.yml`
(`lux docker:run` in the app); the plugin adds the vibe service next to it.

```
# config/config.yaml
plugins:
  - vibe            # registers the lux docker:vibe:* tasks
```

```
lux docker:vibe:init   # writes config/docker/{docker-compose.vibe.yml,Dockerfile.vibe,entrypoint.vibe.sh}
                       # and config/docker/vibe/{opencode.json,instructions.md}; adds OPENROUTER_API_KEY,
                       # VIBE_MODEL, VIBE_GIT_NAME/EMAIL to .env; ignores local/opencode
# put your OpenRouter key into .env
lux docker:vibe:run    # docker compose --project-directory . --profile vibe -f config/docker/docker-compose.yml \
                       #   -f config/docker/docker-compose.vibe.yml [-f config/docker/docker-compose.override.yml] up
open http://localhost:4000
```

The vibe service sits behind the compose profile `vibe`, so an app task that loads the
same files without the profile (`lux docker:run`) starts app + db only.

The generated files are meant to be committed; they are plain compose/docker/json and
`--force` regenerates them from the plugin templates.

A personal `config/docker/docker-compose.override.yml` is loaded last. Compose merges
volumes per service, so an override that remounts live gem checkouts for `app` must
repeat those volumes under `vibe:` as well (the harness runs `bundle exec lux` on the
same checkout); `lux docker:vibe:run` warns when the override has `app:` but no `vibe:`.

`sinatra` and `puma` must be in the app's Gemfile (`group :manual` is enough - the
harness is started with `bundle exec lux docker:vibe:server`). The page needs
`@dinoreic/fez` (`dist/fez.js`) from the app's `node_modules` or `.gems/fez`.

## Tasks

```
lux docker:vibe:init [--force]        generate the harness files into this app
lux docker:vibe:run [--build] [-d]    start app + db + vibe;  --stop = compose down
lux docker:vibe:server                run the harness web app (the vibe container command)
lux docker:vibe:oc [--port 4096]      run opencode serve for this checkout (host debugging)
lux docker:vibe:status                branch, changes, ahead/behind, recent log
lux docker:vibe:commit [-m msg] [-p]  stage all + commit (message generated when omitted), -p pushes
lux docker:vibe:push / :pull          push (rebase on rejection) / pull --rebase origin/vibe
lux docker:vibe:merge                 merge main into vibe
lux docker:vibe:reset [-y]            discard all uncommitted changes
lux docker:vibe:restart [--hard]      soft (tmp/restart.txt) or hard (container restart)
lux docker:vibe:logs                  compose logs -f vibe app
```

The git tasks run on the host checkout with the same `Vibe::Git` code the UI uses.

## Environment (all optional except the key)

| var | default | meaning |
| --- | --- | --- |
| `OPENROUTER_API_KEY` | - | model access for the agent and the commit-message helper |
| `VIBE_MODEL` | `openrouter/anthropic/claude-sonnet-4.5` | opencode model id |
| `VIBE_COMMIT_MODEL` | `anthropic/claude-haiku-4.5` | OpenRouter model for "auto message" |
| `VIBE_BRANCH` / `VIBE_MAIN` | `vibe` / `main` | harness branch, merge source |
| `VIBE_ROOT` | cwd | checkout (`/app` in the container) |
| `VIBE_PORT` | `4000` | harness port |
| `VIBE_APP_URL` | `http://localhost:3000` | what the preview iframes |
| `VIBE_APP_HEALTH_URL` | `VIBE_APP_URL` | what the harness pings (`http://app:3000` in compose) |
| `VIBE_OC_URL` | `http://127.0.0.1:4096` | opencode server |
| `VIBE_APP_SERVICE` | `app` | compose service to hard-restart |
| `VIBE_GIT_NAME` / `VIBE_GIT_EMAIL` | host git config | commit identity inside the container |
| `OPENCODE_CONFIG` | - | set to `/app/config/docker/vibe/opencode.json` by the compose file |

## Debugging without docker

```
lux docker:vibe:oc                                   # opencode on 127.0.0.1:4096 with config/docker/vibe/opencode.json
VIBE_OC_URL=http://127.0.0.1:4096 lux docker:vibe:server   # harness on :4000 against the host checkout
lux s                                                # the app itself on :3000
```

## Layout

```
plugins/vibe/
  hammer/vibe_hammer.rb      lux docker:vibe:* tasks
  lib/vibe.rb                config from ENV, run()
  lib/vibe/git.rb            branch guard + git ops
  lib/vibe/restart.rb        soft / hard restart, container logs
  lib/vibe/opencode.rb       opencode http client
  lib/vibe/commit_message.rb OpenRouter commit message
  lib/vibe/server.rb         Sinatra: page, /api/*, /oc/* proxy (SSE-safe)
  app/                       index.html.erb, style.css, vendor/{vibe.js,marked.min.js}, fez/vibe-*.fez
  templates/                 files `lux docker:vibe:init` renders into the app
  spec/                      rspec: git (tmp repos), server (Rack::MockRequest)
```

The page is built with fez components compiled in the browser (`<script fez=...>`), no
bundler step; edit a `.fez` and reload.

## Security note

The agent runs shell in the vibe container with `permission: allow`, and that container
holds the docker socket for the restart button. Whoever reaches :4000 can drive both. It
is a local dev tool; do not expose the port without an identity gate in front.
