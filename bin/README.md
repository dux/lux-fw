## Lux command line helper

> The `lux` CLI is built on lux-hammer.
> Run tasks as `lux <cmd>` in your app home folder.
> `bundle exec hammer <cmd>` is only for the lux-fw checkout's own `Hammerfile` (`hammer test`, `hammer deploy`).
> Core commands live in `bin/cli/*_hammer.rb`; plugins add theirs from `plugins/<name>/hammer/` or `plugins/<name>/Hammerfile` (e.g. `db:*`, `assets:*`).

### Current commands

Core (`bin/cli/`):

```bash
lux agents           # Write or refresh the lux-fw docs pointer in ./AGENTS.md
lux assets:compile   # Build app/assets into public/assets (app defines it in lib/tasks)
lux assets:upload    # Upload LOCAL_PATH to REMOTE_PATH on the app CDN (app defines it in lib/tasks)
lux console          # Start console                                        (alias: c)
lux evaluate CODE    # Eval Ruby in the app context                         (alias: e, eval)
lux hi               # Print hello world
lux mail:pull        # Pull unseen mail from the configured IMAP inbox(es)
lux memory           # Show memory usage
lux new NAME         # Create, set up and start a new Lux application
lux pack             # Build a symlink-flattened, gitignore-clean app copy for rsync deploy
lux procfile         # Run all Procfile services color-prefixed             (alias: pf)
lux render /path     # Render page via Lux.render (lux render /login -t TOKEN -s user_id=1 -i)
lux routes           # Print mounted route tree (verb, path, target, source)
lux secrets          # Edit, show and compile secrets
lux server           # Start web server (puma only)
lux start            # Generate app/assets/*.tmp.* (web_common), then ./Procfile (alias: s)
lux stats            # Print project stats
lux test             # Run tests (Minitest specs under spec/, test/, or rspec) (alias: t)
lux version          # Print the Lux build version
```

Plugins (only when the app lists the plugin):

```bash
lux db:*             # db: am, create, drop, reset, seed, backup, restore, psql, info, check, exec, unescape, test:am, test:drop
lux assets:*         # web_common: generate, build, deploy
lux docker:*         # web_common: build, local, staging, prod; vibe: docker:vibe:*
lux generate         # web_common: model + cell/policy/api/exporter
lux favicon          # favicon: build public/favicon.ico + apple-touch-icon
lux job_runner:*     # job_runner: start, web
```

`lux test` picks the runner once: rspec when the app has `.rspec` or rspec in its Gemfile, else Minitest specs under `spec/` (`ruby -Ilib -Ispec`) when `spec/` exists, else Minitest under `test/`.

`lux render /path -i` runs one request through the full stack and prints
status, headers, session and `dispatch` - the router, action, template
and layout that served it.
`-t TOKEN` sends `Authorization: Bearer TOKEN`; with the authcog plugin in dev an email address impersonates that user.
`-H K=V` adds request headers, `-s` / `-c` set session keys and cookies, `-p` sets params (query for GET, body otherwise).

### lux-api

`lux-api` is installed with the gem, next to `lux`.
It calls a `Lux::Api` endpoint over HTTP and prints the answer as JSON (`--yaml`, `--text`):

```sh
LUX_API_HOST=http://lvh.me:3000/api lux-api users/login email=foo@bar.com pass=secret
```

`LUX_API_HOST` (required) is the API base URL; `LUX_API_BEARER` (optional) is sent as a bearer token.
Run it with `--help` for the full usage.

### Port

`lux s` resolves the dev port once - `-p 3001`, else `$PORT` (a shell variable
or the app's `.env`), else 3000 - and exports it, so every `./Procfile` service
inherits the same number:

```sh
lux s              # web on 3000, livereload on 35729
PORT=3001 lux s    # web on 3001, livereload on 35730
lux s -p 3002      # -p wins over an exported PORT
```

LiveReload follows the app port as `35729 + (PORT - 3000)`, so two apps running
side by side never share a reload server. `LIVERELOAD_PORT` overrides it.

A Procfile line that assigns `PORT` itself (`web: PORT=3000 bundle exec lux
server`) shadows all of this - leave the port off the line.

### New applications

Run `lux new my-app` from the parent directory.
Hammer's native picker lists the folders under `starter/`; use the arrow keys and Enter to select, or Escape / Ctrl-C to cancel.
When stdin is piped, enter the numbered choice instead.
The command does not load an existing application or overwrite an existing target.
Like every other `lux` command, it refuses to run inside the framework checkout itself.

* `hello-world` - one page with PostgreSQL and AuthCog sign-in. Loads the `db` and `authcog` plugins only, so no plugin files overlay the app. Tailwind and Fez come from a CDN and the navigation is a Fez component, so there is no JavaScript toolchain and no build step.
* `full-minimal` - a public promo page at `/`, a signed-in workspace at `/app`, and an admin-only overview at `/admin`. Loads `web_common` too, so it gets the html builders and the `/admin` area. No JavaScript toolchain either.

The app name supplies the display name and PostgreSQL database prefix: `my-app` becomes `my_app_development`.
Each app receives a fresh session secret in its Git-ignored `config/config.yaml`.
Both ship a `Procfile` and a `config/puma.rb` that calls `lux_boot`, and both load Tailwind through PostWind and Fez from pinned CDN script tags.
Neither starter carries a `package.json`; `lux new` runs `bun install` only for one that does.
The generated README explains the routes, frontend components, production configuration and first-admin setup.
Starter files ending in `.template` lose that suffix when copied, so `.gitignore.template` becomes the app's `.gitignore` without hiding configuration templates in the framework repository.

After generation the command enters the app folder and runs:

```sh
bundle install
bun install                            # only when the starter has a package.json
psql --host=localhost --dbname=my_app_development --command='' || createdb --host=localhost my_app_development
bundle exec lux db:am
bundle exec lux s
```

Setup uses the generated app's bundle and development database.
The database step connects before it creates, so setup can be re-run over a database that already exists.
When invoked from a local Lux checkout, the generator links every checkout the starter declares into `./.libs`: each `lgem 'name'` in the Gemfile and each `"file:.libs/name"` in `package.json`, whichever exist next to the Lux checkout.
An installed Lux gem links nothing; `lgem` then falls back to the RubyGems gem, pinned exactly (`'= X.Y.Z'`) to the version that ran `lux new` (no pin for a `dev` build or an unresolvable version).
Both starters declare lux-fw with `lgem`.
It also writes the app's `AGENTS.md` with a marked block that points coding agents at the framework docs: `.libs/lux-fw/AGENTS.md` for a linked checkout, the installed gem's absolute path otherwise.
`lux agents` rewrites only that block, so run it after upgrading lux-fw; the rest of the file is the app's own.
A failed step stops setup and leaves the generated files in place.
The server runs in the foreground at http://lvh.me:3000; press Ctrl-C to stop it.
To restart, enter the app directory and run `bundle exec lux s`.
