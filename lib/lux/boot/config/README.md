# Lux::Boot::Config

YAML config + `.env` loader + lifecycle hooks. Indifferent access.

`Lux.config` returns the merged config hash; `Lux.secrets` is an alias.
`Lux.dotenv` is the Rails-style `.env` loader, called once at boot.

## Full example

```yaml
# config/config.yaml
default:
  host: localhost:3000
  db:   postgres://localhost/myapp

production:
  host: myapp.com
  db:
    main: postgres://prod-host/myapp
    log:  postgres://prod-host/myapp_log
```

```ruby
# --- reads (host/db merged from default + current env) -----------------

Lux.config.host                  # 'myapp.com' in prod, 'localhost:3000' otherwise
Lux.config[:host]                # symbol or string, both work
Lux.config.db.main               # nested access
Lux.config.all                   # full merged hash
Lux.secrets                      # alias for Lux.config

# Production section is ALWAYS under Lux.config.production in any env -
# deploy tools can read it without LUX_ENV=production.
Lux.config.production.db.main

# --- runtime writes ----------------------------------------------------

Lux.config.host = 'other.com'    # write at runtime

# --- defaults you typically set in config/initializers/lux.rb ----------

Lux.config.app_timeout         = 30
Lux.config.delay_timeout       = 30
Lux.config.use_autoroutes      = false
Lux.config.serve_static_files  = true
Lux.config.log_level           = :info

# logger config
Lux.config.logger_path_mask     = './log/%s.log'
Lux.config.logger_files_to_keep = 3
Lux.config.logger_file_max_size = 10_240_000
Lux.config.logger_formatter do |severity, datetime, _progname, msg|
  "[#{datetime.utc}] #{severity}: #{msg}\n"
end
Lux.config.logger_output_location do |name|
  Lux.env.prod? ? "./log/#{name}.log" : STDOUT
end

# session
Lux.config[:session_cookie_name]      = '_app_session'
Lux.config[:session_cookie_max_age]   = 30.days
Lux.config[:session_forced_validity]  = nil

# csrf opt-out (default on)
Lux.config.csrf                = false

# browser-state root namespace (default 'app'; see Lux::Browser)
Lux.config.browser_namespace   = 'app'

# --- hooks -------------------------------------------------------------

Lux.config.on_reload_code do
  $live_require_check ||= Time.now
  watched = $LOADED_FEATURES.select { |f| File.exist?(f) && File.mtime(f) > $live_require_check }
  watched.each { |f| load f }
  $live_require_check = Time.now
end

Lux.config.on_mail_send do |mail|
  Lux.logger(:email).info "[#{self.class}.#{@_template}] #{mail.subject}"
end

# --- .env loading ------------------------------------------------------

Lux.dotenv     # loads, returns list of files actually loaded
# load order (most specific wins, Dotenv.load is non-destructive):
#   .env.<env>.local  ->  .env.local  ->  .env.<env>  ->  .env
# Env name resolves from LUX_ENV, then RACK_ENV, defaulting to 'development'.

# --- env name ----------------------------------------------------------

Lux.init_env   # resolve and freeze LUX_ENV from RACK_ENV if not set; returns it
```

## Plugin config

Plugins may ship `plugins/<name>/config.yaml`. During `Lux.plugin :name`,
the plugin config is merged into `Lux.config` before the plugin loader
and `load/` files run. It follows the same `default` plus current-env
shape as app config.

If a plugin config contains a top-level `plugins:` list, those plugin
names append to the configured plugin list instead of replacing it. Use
this for small dependency chains between plugins; keep ordering-sensitive
boot logic in the plugin loader.

## See also

* [`../../environment/README.md`](../../environment/README.md) - env / mode / runtime
* [`../../logger/README.md`](../../logger/README.md) - logger config
* [`../../plugin/README.md`](../../plugin/README.md) - plugin load and config order
