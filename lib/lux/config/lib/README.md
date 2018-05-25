## Lux::Config::Secrets

Similar to rails 5.1+, we can encode secrets for easy config.

* using JWT HS512
* create and write sectes in YAML format in `./tmp/secrets.yaml`
* run `lux secrets` to compile secretes to `./config/secrets.txt`
* use "shared" hash for shared secrets
* sectets are available in app via `Lux.secrets`, as struct object

### lux secrets

* compiles unencoded sectes from `./tmp/secrets.yaml` to `./config/secrets.txt`
* creates editable file `./tmp/secrets.yaml` from `./config/secrets.txt` if one exists
* shows available secrets for current environment

### Example

Env development

Secrets file `./tmp/secrets.yaml`

```
shared:
  x: s
  b:
    c: nested

production:
  a: p

development:
  a: d
```

`lux secrets` - will compile secrets or create template if needed

`lux c` - console

```
Lux.secrets.a == "d"
Lux.secrets.x == "s"
Lux.secrets.b.c == "nested"
```

