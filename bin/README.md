# Lux command line helper

If you run command `lux` in your app home folder, you will see something like this.

```
[master] $ lux
Lux (/Users/dux/dev/apps/my/gems/lux-fw, v0.5.20)
Commands:
  lux config          # Show server config
  lux console         # Start console
  lux dbconsole       # Get PSQL console for current database
  lux evaluate        # Eval ruby string in context of Lux::Application
  lux generate        # Genrate models, cells, ...
  lux get             # Get single page by path "lux get /login"
  lux help [COMMAND]  # Describe available commands or one specific command
  lux routes          # Print routes
  lux secrets         # Edit, show and compile secrets
  lux server          # Start web server
  lux stats           # Print project stats

Or use one of rake tasks
  rake assets:clear      # Clear all assets
  rake assets:compile    # Compile assets to public/assets and generate mainifest.json
  rake assets:install    # Install all needed packages via yarn
  rake assets:monitor    # Monitor for file changes
  rake assets:s3_upload  # Upload assets to S3
  rake assets:show       # Show all files/data in manifest
  rake db:am             # Automigrate schema
  rake exceptions        # Show exceptions
  rake exceptions:clear  # Clear all excpetions
  rake nginx:edit        # Edit nginx config
  rake nginx:generate    # Generate sample config
```