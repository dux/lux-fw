module LuxDocker
  # Single source of truth for deploy.json keys.
  # Consumed by:
  #   * `docker:prepare` (injected into the AI prompt so the model knows the schema)
  #   * README's Config section
  #
  # Categories used below:
  #   * required    - must appear in deploy.json
  #   * defaulted   - has a sensible default; omit unless overriding
  #   * locked      - plugin owns it; validator REJECTS if present in deploy.json
  SCHEMA ||= <<~MARKDOWN.freeze
    # deploy.json schema

    Profiles inherit from `default`. A profile may set `extends: <name>` to
    inherit from another profile. CLI flags always win over JSON.

    ## Required keys

    | key        | type   | example                  | notes |
    | ---------- | ------ | ------------------------ | ----- |
    | `app`      | string | `"authcog"`              | kebab-case, used in image names + path |
    | `server`   | string | `"root@1.2.3.4"`         | SSH target; passwordless sudo required |
    | `services` | map    | see services shape below | at least one service |

    ## Defaulted keys (omit unless you really want to override)

    | key            | default     | notes |
    | -------------- | ----------- | ----- |
    | `service_user` | `"deployer"` | system user that owns app files on the host |
    | `env`          | `{}`        | runtime env for containers (see env semantics) |
    | `tls`          | none        | required ONLY when any domain is a wildcard |

    ## Locked keys (validator REJECTS these if present)

    These are derived by the plugin. Don't put them in deploy.json.

    | key         | derivation |
    | ----------- | ---------- |
    | `root`      | `/home/<service_user>/lux-apps` |
    | `compose`   | `["config/docker/compose.yml"]`, auto-appends `config/docker/compose.<profile>.yml` if it exists |
    | `image_tag` | `git rev-parse --short HEAD`, or `"latest"` if not in git; CLI `--image-tag` overrides |
    | `images`    | `{ <svc>: "<app>-<svc>:<image_tag>" }` for each entry in `services` |

    ## services.<key> shape

    Each entry under `services:` describes one logical service.

    | field            | type        | required | notes |
    | ---------------- | ----------- | -------- | ----- |
    | `compose_service`| string      | no       | defaults to the key; matches a service name in compose.yml |
    | `host_port`      | int \\| null | yes      | explicit loopback port Caddy proxies to, or `null` to allocate from `port_range` |
    | `port_range`     | `[lo, hi]`  | when `host_port: null` | both ends 1024..65535, lo <= hi |
    | `container_port` | int         | no       | documentation only, not enforced |
    | `domains`        | `[string]`  | yes      | DNS names this service serves. Wildcard `"*.example.com"` is allowed and **requires** a `tls` block on the profile |
    | `healthcheck`    | object      | no       | `{ path: "/", expect_status: [200,...], timeout: 30 }` |

    Background workers (no public routing) still belong here so compose owns
    them; just omit `host_port` and `domains` is not required if the service
    won't ever be exposed.

    ## env semantics

    Values map to one of:

    | value             | behavior |
    | ----------------- | -------- |
    | `"literal"`       | string written verbatim |
    | `true`            | read from caller's shell ENV at deploy time; deploy fails if unset |
    | `false` / `null`  | passthrough if locally set, otherwise omitted |
    | `"$generate"`     | 64-hex secret generated on first deploy, reused thereafter (stored in remote `shared/.env`) |

    ## Placeholders in any string value

    | placeholder           | resolves to |
    | --------------------- | ----------- |
    | `{{app}}`             | the app identifier |
    | `{{app_underscored}}` | `app` with `-` replaced by `_` |
    | `{{profile}}`         | the active profile name |
    | `{{image_tag}}`       | resolved image tag |
    | `{{host}}`            | `host.docker.internal`; for containers reaching a service running on the host. Compose must declare `extra_hosts: ["host.docker.internal:host-gateway"]` per service (enforced by preflight) |
    | `{{service_user}}`    | OS user the container effectively connects as for host-side resources: local OS user (`$USER`) under `docker:run`, configured `service_user` (default `deployer`) under deploy. Use in DB URLs and similar so the same string works in both contexts |
    | `{{config.a.b.c}}`    | `Lux.config.dig(:a, :b, :c)` (caller-side) |
    | `{{env.KEY}}`         | the resolved value of another env entry (after `$generate` and CLI overrides) |

    ## tls block (only when wildcards are used)

    Exactly one of `api_token` (literal) or `api_token_env` (env var name)
    must be set. The plugin writes the resolved token to
    `/etc/caddy/caddy.env` on the host (root:caddy 0640) at deploy time.

    Env-var form (recommended for shared repos - keeps the secret out of git):

    ```json
    "tls": {
      "dns_provider": "cloudflare",
      "api_token_env": "CLOUDFLARE_API_TOKEN"
    }
    ```

    Then `export CLOUDFLARE_API_TOKEN=...` before running deploy.

    Literal form (single-dev convenience - **token is in the file, gitignore
    deploy.json or accept the leak risk**):

    ```json
    "tls": {
      "dns_provider": "cloudflare",
      "api_token": "cfut_..."
    }
    ```

    * `dns_provider` - one of: `cloudflare`. Adding others requires a Caddy
      build that includes `github.com/caddy-dns/<name>` and a tweak to
      `LuxDocker::Config::TLS_DNS_PROVIDERS`.

    ## Minimal example

    ```json
    {
      "default": {
        "app": "myapp",
        "server": "root@1.2.3.4",
        "env": {
          "RACK_ENV": "production",
          "SECRET_KEY_BASE": "$generate",
          "DB_URL": "postgresql://app@{{host}}/myapp"
        },
        "services": {
          "web": {
            "host_port": 3100,
            "container_port": 3000,
            "domains": ["myapp.com", "www.myapp.com"]
          }
        }
      }
    }
    ```

    ## Wildcard / TLS example

    ```json
    {
      "default": {
        "app": "myapp",
        "server": "root@1.2.3.4",
        "tls": {
          "dns_provider": "cloudflare",
          "api_token_env": "CLOUDFLARE_API_TOKEN"
        },
        "env": { "RACK_ENV": "production", "SECRET_KEY_BASE": "$generate" },
        "services": {
          "web": {
            "host_port": 3100,
            "container_port": 3000,
            "domains": ["myapp.com", "*.myapp.com"]
          }
        }
      }
    }
    ```

    Before `lux docker:server:deploy`: `export CLOUDFLARE_API_TOKEN=...`
  MARKDOWN
end
