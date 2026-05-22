# Lux::Config - agent guide

YAML config + `.env` + lifecycle hooks.

## Canonical example

```ruby
# Read
Lux.config.host                  # string/symbol both work
Lux.config[:db]                  # may be string or hash (multi-db)
Lux.config.production.db         # production deploy config, in any env

# Write at runtime
Lux.config.app_timeout = 30

# Hooks
Lux.config.on_reload_code { ... }       # called when Lux::Reloader fires
Lux.config.on_mail_send  { |mail| ... } # called for every outgoing mail

# Custom logger output / formatter
Lux.config.logger_output_location do |name|
  Lux.env.prod? ? "./log/#{name}.log" : STDOUT
end
```

## Rules

* **`Lux.config`** is the global YAML config (indifferent access). Loaded
  from `config/config.yaml`, merged: `default` -> `<env>`.
* **Keep production deploy config reachable.** `Lux.config.production`
  exists even when `Lux.env` is development or test so tooling can read
  deploy-only settings without changing the process environment.
* **`Lux.secrets`** is an alias - use whichever feels right semantically
  (`Lux.secrets[:stripe_key]` vs `Lux.config[:host]`).
* **Plugin config merges during plugin load.** A plugin's
  `plugins/<name>/config.yaml` is merged into `Lux.config` before that
  plugin's `loader.rb` and `load/` files run. A top-level `plugins:` list
  appends to the configured plugin list instead of replacing it.
* **`.env` loads automatically** via `Lux.dotenv` during boot. Order:
  `.env.<env>.local`, `.env.local`, `.env.<env>`, `.env`. Don't `require
  'dotenv'` yourself.
* **Lifecycle hooks** are blocks stored on the config. Common ones:
  * `on_reload_code` - hook into `Lux::Reloader.run`
  * `on_mail_send` - log/audit outgoing mail
  * `logger_output_location` - return path or IO for a named logger
  * `logger_formatter` - custom format proc
* **Don't reach for ENV** when the value is in `config.yaml` - go through
  `Lux.config`. `.env` lands in `ENV`; config.yaml lands in `Lux.config`;
  the layers are intentional.

## Don't

* Hardcode secrets in `config.yaml` or commit them. Use `.env.local` or
  `Lux.secrets[:KEY]` via ENV.
* Write to `Lux.config` from inside a request - it's process-wide state.
  Use `current.var` for request-scoped data.

## See also

* [`Lux::Environment` AGENTS](../environment/AGENTS.md)
* [`Lux::Logger` AGENTS](../logger/AGENTS.md)
* [`Lux::Plugin` AGENTS](../plugin/AGENTS.md)
