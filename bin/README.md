## Lux command line helper

You can run command `lux` in your app home folder.

If you have `capistrano` or `mina` installed, you will see linked tasks here as well.

```bash
$ lux
Commands:
  lux config          # Show server config
  lux console         # Start console
  lux erb             # Parse and process *.erb templates
  lux evaluate        # Eval ruby string in context of Lux::Application
  lux generate        # Genrate models, cells, ...
  lux get             # Get single page by path "lux get /login"
  lux help [COMMAND]  # Describe available commands or one specific command
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