# Lux::Config

YAML config + `.env` loader + lifecycle hooks. Indifferent access.

## Small example

```ruby
Lux.config.host                  # 'myapp.com'  (read from config.yaml)
Lux.config.host = 'other.com'    # write at runtime
Lux.config[:host]                # same; symbol or string both work
```

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
# anywhere in the app
Lux.config.host          # 'myapp.com' in prod, 'localhost:3000' in default
Lux.config.all           # full merged hash
Lux.secrets              # alias for Lux.config

# defaults you usually want to set in config/initializers/lux.rb:
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

# session config
Lux.config[:session_cookie_name]      = '_app_session'
Lux.config[:session_cookie_max_age]   = 30.days
Lux.config[:session_forced_validity]  = nil

# hooks
Lux.config.on_reload_code do
  $live_require_check ||= Time.now
  watched = $LOADED_FEATURES.select { |f| File.exist?(f) && File.mtime(f) > $live_require_check }
  watched.each { |f| load f }
  $live_require_check = Time.now
end
Lux.config.on_mail_send do |mail|
  Lux.logger(:email).info "[#{self.class}.#{@_template}] #{mail.subject}"
end
```

## `.env` loading

`Lux.dotenv` is Rails-style and is called once at boot. Load order (most
specific wins, since `Dotenv.load` is non-destructive):

```
.env.<env>.local  ->  .env.local  ->  .env.<env>  ->  .env
```

Env name resolves from `LUX_ENV`, then `RACK_ENV`, defaulting to
`development`. Returns the list of files actually loaded.

## See also

* [`../environment/README.md`](../environment/README.md) - env / mode / runtime
* [`../logger/README.md`](../logger/README.md) - logger config
* [`AGENTS.md`](./AGENTS.md) - LLM guide
