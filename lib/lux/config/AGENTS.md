# Lux::Config - agent guide

YAML config + `.env` + lifecycle hooks.

## Canonical example

```ruby
# Read
Lux.config.host                  # string/symbol both work
Lux.config[:db]                  # may be string or hash (multi-db)

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
  from `config/config.yaml`, merged: `default` → `<env>`.
* **`Lux.secrets`** is an alias - use whichever feels right semantically
  (`Lux.secrets[:stripe_key]` vs `Lux.config[:host]`).
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
