module LuxDeploy
  # `deploy:llm_prepare` bootstraps the Docker artifacts the deploy plugin
  # needs by handing a tailored prompt to the `claude` CLI. The prompt
  # carries:
  #   - what files Claude must create (Dockerfile, compose.yml, compose.staging.yml, config/deploy.json)
  #   - the env/volume/port contract the plugin will set at deploy time
  #   - the parsed Procfile so service names match runtime processes
  #   - a list of questions Claude must ask the operator when something is ambiguous
  module LLMPrepare
    module_function

    def run(opts = {})
      app_root = Config.find_app_root(Dir.pwd)
      procfile = parse_procfile(app_root)
      prompt = build_prompt(app_root: app_root, procfile: procfile, opts: opts)

      if opts[:print]
        puts prompt
        return
      end

      out_dir = File.join(app_root, 'tmp')
      FileUtils.mkdir_p(out_dir)
      prompt_path = File.join(out_dir, 'deploy-llm-prepare-prompt.md')
      File.write(prompt_path, prompt)
      puts "wrote prompt: #{prompt_path}"

      unless command_exists?('claude')
        warn 'claude CLI not found on PATH'
        warn "open the prompt and paste it into a Claude session: #{prompt_path}"
        exit 1
      end

      argv = ['claude', prompt]
      puts "+ claude <prompt from #{prompt_path}>"
      return if opts[:dry_run]
      system(*argv)
      exit $?.exitstatus.to_i unless $?.success?
    end

    def parse_procfile(app_root)
      path = File.join(app_root, 'Procfile')
      return { path: path, exists: false, services: [] } unless File.file?(path)
      services = File.read(path).each_line.map do |line|
        line = line.chomp.strip
        next nil if line.empty? || line.start_with?('#')
        name, cmd = line.split(':', 2)
        next nil unless name && cmd
        { name: name.strip, cmd: cmd.strip }
      end.compact
      { path: path, exists: true, services: services }
    end

    def command_exists?(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, name))
      end
    end

    def build_prompt(app_root:, procfile:, opts:)
      services_section = if procfile[:exists] && !procfile[:services].empty?
        list = procfile[:services].map { |s| "* `#{s[:name]}`: `#{s[:cmd]}`" }.join("\n")
        "Procfile at `#{procfile[:path]}` declares:\n\n#{list}\n"
      elsif procfile[:exists]
        "Procfile at `#{procfile[:path]}` exists but parses to zero services. Ask the operator which services to set up before writing any files."
      else
        "No Procfile found at `#{procfile[:path]}`. Ask the operator which services exist (web, job/worker, socket, admin, etc.) before writing any files."
      end

      <<~PROMPT
        # Task: bootstrap Docker artifacts for the Lux deploy plugin

        You are working inside a Lux Ruby app at `#{app_root}`.
        The deploy plugin at `plugins/deploy/` will ship Docker images of this app
        to a Linux host running Docker and Caddy. You are responsible for
        producing the four files the plugin expects, NOT for running the deploy.

        ## Files to create

        Create these files if missing. If they exist, propose edits before
        overwriting and confirm with the operator.

        1. `config/docker/Dockerfile`
           Multistage build. Stages:
             - `base`     : minimal Ruby (and Node/Bun if needed) runtime
             - `builder`  : installs build deps, runs `bundle install`, precompiles assets
             - `runtime`  : copies vendor/bundle + app + assets from builder, drops build deps
           Set `WORKDIR /app`. Create a non-root `app` user and `USER app`.
           Default `CMD` should boot the web service. Other services override `command:`
           in compose.yml.

        2. `config/docker/compose.yml`
           One service block per logical process. Each service MUST:
             - read `image:` from `${<SVC>_IMAGE:-<svc>-local}` (uppercase service name)
             - declare `build: { context: ${LUX_SOURCE_DIR:-../..}, dockerfile: config/docker/Dockerfile }`
               so `compose build` works both locally and remotely
             - load runtime env from `env_file: ["${LUX_RUNTIME_ENV_FILE:-../../.env}"]`
             - bind-mount logs and tmp:
                 `${LUX_LOG_DIR:-../../log}:/app/log`
                 `${LUX_TMP_DIR:-../../tmp}:/app/tmp`
             - if it serves HTTP, publish to loopback: `127.0.0.1:${<SVC>_PORT:-3000}:3000`
             - `restart: unless-stopped`

        3. `config/docker/compose.staging.yml`
           Adds project-local Postgres (and Redis if the app uses it). Required for
           PR/staging deploys. Pattern:

             services:
               web: { depends_on: [db] }
               <other-services>: { depends_on: [db] }
               db:
                 image: postgres:16
                 restart: unless-stopped
                 environment:
                   POSTGRES_DB: ${POSTGRES_DB:-app}
                   POSTGRES_USER: ${POSTGRES_USER:-app}
                   POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-app}
                 volumes: ["pg-data:/var/lib/postgresql/data"]
                 healthcheck:
                   test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-app}"]
                   interval: 5s
                   timeout: 3s
                   retries: 20
             volumes:
               pg-data:

        4. `config/deploy.json`
           Must follow this exact shape. Profiles inherit from `default`; `staging`
           and `pr` profiles extend it.

             {
               "default": {
                 "server": "<ASK USER: ssh target, e.g. root@srv.example.com>",
                 "env": {
                   "RACK_ENV": "production",
                   "DB_URL": "<ASK USER: postgres URL or use postgres:///{{app_underscored}} for local socket>",
                   "SECRET_KEY_BASE": true
                 },
                 "services": {
                   "<svc>": {
                     "compose_service": "<svc>",
                     "host_port": <ASK USER: explicit port, e.g. 3100>,
                     "container_port": 3000,
                     "domains": ["<ASK USER: domain(s)>"],
                     "healthcheck": { "path": "/", "expect_status": [200, 301, 302] }
                   }
                 }
               },
               "staging": {
                 "env": {
                   "RACK_ENV": "staging",
                   "POSTGRES_DB": "app",
                   "POSTGRES_USER": "app",
                   "POSTGRES_PASSWORD": "$generate",
                   "DB_URL": "postgres://app:{{env.POSTGRES_PASSWORD}}@db:5432/app"
                 },
                 "services": {
                   "<svc>": {
                     "compose_service": "<svc>",
                     "host_port": null,
                     "port_range": [3500, 3899],
                     "domains": ["{{app}}.staging.<ASK USER: staging-base>"]
                   }
                 }
               },
               "pr": { "extends": "staging" }
             }

           Rules:
             - `env` values are: `"literal"` | `true` (required from operator's shell) | `false`/null (passthrough if set) | `"$generate"` (stable 64-hex secret kept in remote .env)
             - Placeholders allowed in strings: `{{app}}`, `{{app_underscored}}`, `{{profile}}`, `{{image_tag}}`, `{{host}}` (docker bridge gateway), `{{config.a.b.c}}` (reads Lux.config), `{{env.KEY}}` (reads another env value after resolution)
             - The plugin auto-derives `images`, `image_tag`, `compose`, and `root` - do NOT include them in deploy.json (the validator rejects them). Images get named `<app>-<svc>:<image_tag>`; image_tag comes from `git rev-parse --short HEAD`; compose files auto-detected (compose.yml + compose.<profile>.yml if present); root fixed at `/home/<service_user>/lux-apps`.
             - `service_user` defaults to `deployer` and rarely needs to be set; include it only if app files should be owned by a different system user.
             - One logical service per `services.*` entry. Background workers/jobs (non-HTTP) still belong here so compose owns them, but they should NOT publish ports or carry `domains`. If a service does not need public routing, omit it from `services.*` entirely and define it only in compose.yml. The plugin only generates Caddy blocks for `services.*` entries that have a `host_port` AND `domains`.

        ## What the deploy plugin will set at runtime

        At deploy time the plugin writes `/srv/lux-apps/<app>/config/docker/deploy.env`
        with these keys, then runs `docker compose --env-file ...`. Your compose.yml
        only needs to reference them via `${...}`:

          LUX_RUNTIME_ENV_FILE  - absolute path to the per-app .env, 0600
          LUX_LOG_DIR           - bind mount target for /app/log
          LUX_TMP_DIR           - bind mount target for /app/tmp
          LUX_SOURCE_DIR        - app root (used only for compose build context)
          COMPOSE_PROJECT_NAME  - lux-<app>
          <SVC>_IMAGE           - one per logical service (matches `images.*`)
          <SVC>_PORT            - one per service that publishes (matches `services.*.host_port`)

        Never assume host paths. Always use the env vars above.

        ## Procfile / service mapping

        #{services_section}

        Use the Procfile names verbatim as both `services.*` keys in deploy.json and
        the service name in compose.yml. If the Procfile has a `web`, it becomes the
        HTTP service. Anything with `job`, `worker`, `runner` is a background worker:
        no `ports:`, no domain, but still a compose service so it boots with the
        stack.

        ## Questions you MUST ask the operator

        Do not invent values for any of these. If unknown, ask and stop until
        answered:

        1. **App identifier** — short kebab-case name. If unclear, suggest the
           directory basename or what the operator has called the project.
        2. **SSH target** — `user@host` for production. Plugin needs passwordless
           sudo for that user. If the operator has multiple hosts (staging vs prod)
           ask whether they want one host or two.
        3. **Domains per service** — exact list. Include redirects (e.g.
           `acme.com` and `www.acme.com`). For staging, ask for a base like
           `staging.acme.com` so `{{app}}.staging.acme.com` resolves.
        4. **Image registry strategy** — confirm the operator wants the default
           archive transport (`docker save | gzip`). Only suggest registry mode if
           they bring it up.
        5. **Image tag scheme** — `latest`, git SHA, or CI build id. Default to
           `latest` unless they prefer something pinned.
        6. **Database** — production uses a real Postgres (URL via `DB_URL`).
           Confirm whether it lives on the same host, an external managed DB, or
           inside compose. If inside compose, add `db` to compose.yml not just
           compose.staging.yml.
        7. **Required env keys** — anything beyond `SECRET_KEY_BASE` that the app
           reads at boot. Ask the operator to enumerate them. Mark each as
           `true` (required), `"literal"`, or `"$generate"`.
        8. **Healthcheck path per service** — default `/`. Ask if any service has
           a dedicated `/health` route.
        9. **Production host_port** — explicit number per service. For PR/staging
           use `port_range`. Pick non-overlapping ranges if multiple services need
           auto-allocation.
        10. **Build dependencies** — list of native gems / system packages the
            Dockerfile builder stage must install (postgres dev headers, node,
            bun, image libs, etc.). Ask if you cannot infer from Gemfile and
            package.json.

        ## Output

        When done:
          - List every file you created or modified with a one-line reason
          - Print the exact next commands the operator should run:
              lux deploy:build
              lux deploy:test
              lux deploy
          - If config/deploy.json had unresolved `<ASK USER: ...>` placeholders,
            stop and list them.

        Do not run the deploy. Do not modify anything outside `config/`.
      PROMPT
    end
  end
end
