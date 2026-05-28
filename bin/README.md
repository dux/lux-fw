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
  lux mount       # Symlink missing entries from each plugin's mount/ into the app root
  lux render      # Render page via Lux.render (lux render /login -t TOKEN -s user_id=1 -i)
  lux routes      # Print mounted route tree (verb, path, target, source)
  lux secrets     # Edit, show and compile secrets
  lux server      # Start web server                                    (alias: s)
  lux stats       # Print project stats
  lux test        # Run tests (auto-detects rspec or minitest)          (alias: t)
```

Run tests with `lux test` or `bundle exec hammer test`.

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
