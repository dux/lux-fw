# {{App}}

A minimal promo site, authenticated workspace and admin area, inspired by Soho Tasks, with PostgreSQL, AuthCog sign-in, PostWind and Fez.

## Start

`lux new` installs the bundle, creates the PostgreSQL database, migrates the schemas and starts the server automatically.
Ruby, PostgreSQL and Bundler must already be installed.
Press Ctrl-C to stop the server.
To start it again from this directory:

```sh
bundle exec lux s
```

Open http://lvh.me:3000.
`lux s` compiles the auto assets and then runs `./Procfile`, which starts the rollup watcher and the server.
Use `lux s -p 3001` or `PORT=3001 lux s` to serve on another port; LiveReload follows it.
The database name comes from the application name.
`lux db:am` loads the model schemas through `./db/auto_migrate.rb`.
All `lux` commands use Hammer; run `lux --help` to see the available tasks.

## Local gem and library checkouts

The Gemfile resolves each `lgem` from `./.gems/<name>` when that directory
exists, and from `github dux/<name>` when it does not, so a fresh clone with no
`.gems` still installs.
`package.json` pulls Fez and PostWind from `./.gems` the same way.
Generating from a local Lux checkout links every one of them that is present
next to it.
The `.gems` directory is ignored by Git.

## JavaScript

`bun` is required. `lux new` runs `bun install` for you.
`./Procfile` runs `bun x rollup -cw`, which bundles `./app/assets/auto-*.tmp.js`
into `./public/assets/`, compiles the SCSS, and serves LiveReload.
`web_common` supplies `rollup.config.js`, which `lux assets:auto` (run by
`lux s`) copies into the app root, so there is no build config to maintain here.

## Routes and authentication

* `/` - public promo page.
* `/about` - what this starter is.
* `/app` - workspace; guests go to sign-in, then return here.
* `/admin` - overview, available only to administrators.
* `/login` - redirects to AuthCog for the current host and port.
* `/authcog?callback=...` - exchanges the AuthCog callback for a local session.

Routes live in `./app/routes.rb`.
`UserSession.resolve` restores the current user before routing and handles signed logout links.
Locked and deleted users cannot keep an active local session.

`PromoController` is mounted as `call 'promo#auto'`, the convention router from `Lux::Controller::Auto`.
Public pages need no action and no route line: drop `./app/views/promo/NAME.haml` and `/NAME` serves it.
`/app` and `/admin` are mounted explicitly, because they carry access rules.

## Frontend

`./app/views/layouts/main.haml` loads pinned PostWind and Fez releases from jsDelivr.
PostWind loads the Tailwind browser runtime and styles HAML and Fez components without a build step.
Browser internet access is required for these scripts.
Edit `./public/components/starter-counter.fez` for the sample reactive component.
Use `<script fez="/components/name.fez"></script>` to load another component.

## Navigation

Fez ships Pjax, and binds it when the page declares a container - the layout's `%main#page.pjax`.
Following a link then fetches the new page over XHR and swaps only that node, so the browser keeps its scroll, its assets and any state living outside `<main>`.
Remove the `pjax` class to go back to full page loads, or put `no-pjax` on a single link to opt that one out.
The nav is rendered outside the container and is never swapped, so the sign-in and sign-out links carry `no-pjax`.

## Configuration

`./config/config.yaml` contains the generated session secret and database URLs and is ignored by Git.
Keep this file when deploying, or provision the configuration on the host.
Set `LUX_ENV=production`, configure the production host and database, and provide a stable secret shared by all app processes.
`DB_MAIN` can override the database URL.

## First administrator

Sign in once, then open `lux c` and promote your account:

```ruby
User.first(email: 'you@example.com').update(is_admin: true)
```

Reload the page to see the Admin navigation link.
Admin access is checked on the server through `UserPolicy`; new accounts are not administrators.
