# {{App}}

A minimal Lux application: two pages, PostgreSQL, AuthCog sign-in, and a Fez
navigation component styled with Tailwind. No build step and no JavaScript
toolchain.

## Start

`lux new` installs the bundle, creates the PostgreSQL database, migrates the
schemas and starts the server automatically.
Ruby, PostgreSQL and Bundler must already be installed.
Press Ctrl-C to stop the server.
To start it again from this directory:

```sh
bundle exec lux s
```

Open http://lvh.me:3000.
`lux s` runs `./Procfile`, whose single `web` line starts the server.
Use `lux s -p 3001` or `PORT=3001 lux s` to serve on another port.
The database name comes from the application name.
`lux db:am` loads the model schemas through `./db/auto_migrate.rb`.
All `lux` commands use Hammer; run `lux --help` to see the available tasks.

## Plugins

`./config/config.yaml` loads two plugins:

* `db` - Sequel models, the schema DSL and `lux db:am`.
* `authcog` - `AuthcogController` and `UserSession`.

The larger `web_common` plugin is deliberately absent. It brings html builders,
an asset pipeline, an exception logger and an `/admin` area, and it symlinks
about forty files into the app. Add it to the list when you want them.

## Routes and authentication

* `/` - the page. Shows a sign-in button, or `Hello NAME` once signed in.
* `/about` - what this starter is.
* `/login` - redirects to AuthCog for the current host and port.
* `/authcog?callback=...` - exchanges the AuthCog callback for a local session.

Routes live in `./app/routes.rb`.
`UserSession.resolve` restores the current user before routing and handles
signed logout links.
Locked and deleted users cannot keep an active local session.

## Frontend

`./app/views/layouts/main.haml` loads pinned PostWind and Fez releases from
jsDelivr. PostWind loads the Tailwind browser runtime and styles HAML and Fez
components without a build step. Browser internet access is required for these
scripts.

`ApplicationController` exports the current user to the page:

```ruby
lux.browser.window[:app][:current] = { user: ... }
```

`= lux.browser.window_script` in the layout head emits that as
`<script id="lux-state">`, so the browser sees `window.app.current.user`.
`./public/components/app-nav.fez` reads it and renders either a sign-in link or
the user's name plus a sign-out link.

Add a component by dropping a `.fez` file in `./public/components/` and loading
it with `<script fez="/components/name.fez"></script>`. The file name is the tag
name, so `app-nav.fez` defines `<app-nav>`. Fez compiles it in the browser.

## Navigation

Fez ships Pjax, and binds it when the page declares a container - the layout's
`%main#page.pjax`. Following a link then fetches the new page over XHR and swaps
only that node, so the browser keeps its scroll, its assets and any state living
outside `<main>`. Remove the `pjax` class to go back to full page loads, or put
`no-pjax` on a single link to opt that one out.

The nav is outside the container, so it is never swapped. Pjax re-runs the
layout's inline `<head>` scripts on every navigation, which refreshes
`window.app`; `app-nav.fez` listens for `pjax:render` and re-reads it, so
signing out updates the nav without a reload.

## Configuration

`./config/config.yaml` contains the generated session secret and database URLs
and is ignored by Git.
Keep this file when deploying, or provision the configuration on the host.
Set `LUX_ENV=production`, configure the production host and database, and
provide a stable secret shared by all app processes.
The secret signs the sign-out tokens, so every process needs the same one.
`DB_MAIN` can override the database URL.
Set `authcog_realm` to authenticate against a realm other than `auth`.
