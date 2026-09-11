## Lux command line helper

> NOTE: The `lux` CLI is now built on lux-hammer. The old Thor/Rake setup is
> retired - there is no Rakefile and no `rake ...` tasks. Run tasks as
> `lux <cmd>` (or `bundle exec hammer <cmd>`). The real commands live in
> `bin/cli/*_hammer.rb`. The Thor output and Rake list further down are kept
> only for historical reference and no longer reflect reality.

You can run command `lux` in your app home folder.

### Current commands

```bash
$ lux
  lux console     # Start console                                       (alias: c)
  lux evaluate    # Eval ruby string in context of Lux::Application     (alias: e, eval)
  lux generate    # Generate models, cells, ...
  lux hi          # Print hello world
  lux memory      # Show memory usage
  lux render      # Render page via Lux.render (lux render /login -t TOKEN -s user_id=1 -i)
  lux routes      # Print mounted route tree (verb, path, target, source)
  lux secrets     # Edit, show and compile secrets
  lux server      # Start web server (puma only)
  lux start       # Compile auto assets, then run ./Procfile               (alias: s)
  lux procfile    # Run all Procfile services color-prefixed            (alias: pf)
  lux stats       # Print project stats
  lux test        # Run tests (auto-detects rspec or minitest)          (alias: t)
```

Run tests with `lux test` or `bundle exec hammer test`.

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
* `full-minimal` - a public promo page at `/`, a signed-in workspace at `/app`, and an admin-only overview at `/admin`. Loads `web_common` too, so it gets the html builders, the `/admin` area and the rollup asset pipeline.

The app name supplies the display name and PostgreSQL database prefix: `my-app` becomes `my_app_development`.
Each app receives a fresh session secret in its Git-ignored `config/config.yaml`.
Both ship a `Procfile` and a `config/puma.rb` that calls `lux_boot`, and both load Tailwind through PostWind and Fez from pinned CDN script tags.
Only `full-minimal` carries a `package.json`; `lux new` runs `bun install` when one is present.
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
When invoked from a local Lux checkout, the generator links every checkout the starter declares into `./.gems`: each `lgem 'name'` in the Gemfile and each `"file:.gems/name"` in `package.json`, whichever exist next to the Lux checkout.
An installed Lux gem links nothing; `lgem` then falls back to `github dux/<name>`.
A failed step stops setup and leaves the generated files in place.
The server runs in the foreground at http://lvh.me:3000; press Ctrl-C to stop it.
To restart, enter the app directory and run `bundle exec lux s`.

---

## Superseded (historical Thor/Rake output - no longer accurate)

The sections below describe the retired Thor-based CLI and the old Rakefile
tasks. They are preserved for history only; none of these `rake ...` tasks
exist anymore.

```bash
$ lux
Commands:
  lux console         # Start console
  lux evaluate        # Eval ruby string in context of Lux::Application
  lux generate        # Genrate models, cells, ...
  lux help [COMMAND]  # Describe available commands or one specific command
  lux render          # Render page via Lux.render "lux render /login -t TOKEN -i"
  lux routes          # Print routes
  lux secrets         # Edit, show and compile secrets
  lux server          # Start web server
  lux stats           # Print project stats

Rake tasks:
  rake assets:compile    # Build and generate manifest
  rake assets:install    # Install example rollup.config.js, package.json and Procfile
  rake db:am             # Automigrate schema
  rake db:console        # Run PSQL console
  rake db:create         # Create database
  rake db:drop           # Drop database
  rake db:dump[name]     # Dump database backup
  rake db:reset          # Reset database (drop, create, auto migrate, seed)
  rake db:restore[name]  # Restore database backup
  rake db:seed:gen       # Create seeds from models
  rake db:seed:load      # Load seeds from db/seeds
  rake docker:bash       # Get bash to web server while docker-compose up
  rake docker:build      # Build docker image named stemical
  rake docker:up         # copose up
  rake exceptions        # Show exceptions
  rake exceptions:clear  # Clear all excpetions
  rake images:reupload   # Reupload images to S3
  rake job:process       # Process delayed job que tasks (NSQ, Faktory, ...)
  rake job:start         # Start delayed job que tasks Server (NSQ, Faktory, ...)
  rake nginx:edit        # Edit nginx config
  rake nginx:generate    # Generate sample config
  rake start             # Run local dev server
  rake stat:goaccess     # Goaccess access stat builder
```
