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

Environment sections deep-merge over `default`: hashes merge key by key, every other value replaces.
An env array replaces the default array (`default: plugins: [a]` plus `production: plugins: [b]` gives `[b]`), and an explicit `key: ~` clears a default to `nil`.

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

# --- framework defaults you can override -------------------------------
#
# Declare these in config/config.yaml. The first Lux.config read fills in
# only what you left out (Lux::Boot.apply_defaults), so an explicit `false`
# is never flipped back on, and Lux.logger / Lux.log / Lux.defer work before
# Lux.boot!. log_level and channel_url follow ENV that .env may supply
# (LUX_DEBUG, DB_MAIN), so they are only defaulted by Lux.boot!.

Lux.config.delay_timeout       = 30
Lux.config.serve_static_files  = true
Lux.config.log_level           = :info     # YAML `log_level: info` works too (info / warn / error / debug)
Lux.config.ref_format          = :string   # or :uuid7 / :slug - see Lux::Ref.register

# logger config
Lux.config.logger_path_mask     = './log/%s.log'
Lux.config.logger_files_to_keep = 3
Lux.config.logger_file_max_size = 10_240_000
Lux.config.log_requests         = true   # JSON access log in ./log/request.log (id, method, path, status, ms, ip, user)
Lux.config.logger_formatter do |severity, datetime, _progname, msg|
  "[#{datetime.utc}] #{severity}: #{msg}\n"
end

# CF-* headers (CF-Connecting-IP, CF-IPCountry): trust always (app reachable
# through Cloudflare only); default false drops them unless the forwarding hop
# is a CF edge
Lux.config.cloudflare          = false

# session
Lux.config[:session_cookie_name]      = '_app_session'
Lux.config[:session_cookie_max_age]   = 10.days  # sliding: reissued once a day while in use
Lux.config[:session_cookie_domain]    = nil      # nil = shared on the root domain (__Secure-); false = host-only __Host-; 'example.com' = that domain
Lux.config[:session_ip_check]         = false    # bind session to exact IP (strict, breaks on network switch)
Lux.config[:session_dbsc]             = true     # device-bound sessions over https (Chrome/Edge), see Lux::Context::Dbsc

# csrf opt-out (default on)
Lux.config.csrf                = false

# inbound mail: authserv-ids whose Authentication-Results headers are trusted;
# empty (default) means inbound mail is never `verified`
Lux.config[:mail] = { trusted_authserv_ids: ['mx.example.com'] }

# --- hooks -------------------------------------------------------------

Lux.config.on_mail_send do |mail|
  Lux.logger(:email).info "[#{self.class}.#{@_template}] #{mail.subject}"
end

# --- .env loading ------------------------------------------------------

Lux.dotenv     # loads, returns list of files actually loaded
# load order (most specific wins, Dotenv.load is non-destructive):
#   .env.<env>.local  ->  .env.local  ->  .env.<env>  ->  .env
# Env name resolves from LUX_ENV; when unset, LUX_ENV is peeked from
# .env.local / .env, else 'development'. Lux.boot! loads .env before the
# LUX_ENV check, so LUX_ENV may live in .env.

# --- env name ----------------------------------------------------------

Lux.init_env   # resolve LUX_ENV (default development), mirror into RACK_ENV; returns it
```

## Plugin config

Plugins may ship `plugins/<name>/config.yaml`. During `Lux.plugin :name`,
the plugin config is merged into `Lux.config` before the plugin loader
and `load/` files run. It follows the same `default` plus current-env
shape as app config.

Plugin config fills keys the app did not declare, whole: an app array or `nil` is never merged with the plugin value; a dependent plugin overrides its dependency.
App values (including the framework defaults) are never overwritten; a plugin that must change one does it in its `loader.rb`.

If a plugin config contains a top-level `plugins:` list, those plugin
names append to the configured plugin list instead of replacing it. Use
this for small dependency chains between plugins; keep ordering-sensitive
boot logic in the plugin loader.

## See also

* [`../../environment/README.md`](../../environment/README.md) - env / mode / runtime
* [`../../logger/README.md`](../../logger/README.md) - logger config
* [`../../plugin/README.md`](../../plugin/README.md) - plugin load and config order
