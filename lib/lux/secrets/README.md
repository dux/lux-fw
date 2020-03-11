## Lux.secrets (Lux::Secrets)

Access and protext secrets.

Secrets can be provided in raw yaml file in `./config/secrets.yaml`

#### Protecting secrets file

If you have a secret hash defined in `Lux.config.secret_key_base` or `ENV['SECRET_KEY_BASE']`,
* you can use `bundle exec lux secrets` to compile and secure secrets file (`./config/secrets.yaml`).
* copy of the original file will be placed in `./tmp/secrets.yaml`
* vim editor will be used to edit the secrets file