module LuxDocker
  # `lux docker:prepare` scaffolds the three files this plugin needs for a
  # new project: `config/docker/Dockerfile`, `config/docker/compose.yml`,
  # and `config/docker/deploy.json`. It does the scaffolding by handing a
  # tightly-scoped prompt to the `claude` CLI; the prompt embeds the live
  # SCHEMA from lux_docker_schema.rb so the model never has to guess the
  # config shape.
  module Prepare
    PROMPT_FILE ||= 'tmp/lux-prepare-prompt.md'

    module_function

    def run(opts = {})
      app_root = Config.find_app_root(Dir.pwd)
      guard_overwrite!(app_root, opts)
      hints = collect_hints(app_root)
      prompt = build_prompt(app_root: app_root, hints: hints)

      if opts[:print]
        puts prompt
        return
      end

      prompt_path = File.join(app_root, PROMPT_FILE)
      FileUtils.mkdir_p(File.dirname(prompt_path))
      File.write(prompt_path, prompt)
      puts "wrote prompt: #{prompt_path}"

      unless command_exists?('claude')
        warn 'claude CLI not found on PATH'
        warn "open the prompt and paste it into a Claude session: #{prompt_path}"
        exit 1
      end

      puts "+ claude < #{prompt_path}"
      return if opts[:dry_run]
      system('claude', prompt)
      exit $?.exitstatus.to_i unless $?.success?

      puts
      puts 'Next:'
      puts '  lux docker:run                  # validate locally'
      puts '  lux docker:server:prepare       # provision the host'
      puts '  lux docker:server:deploy        # ship it'
    end

    # Refuse to clobber an existing deploy.json without --force. Keeps the
    # command safe to rerun for discovery without losing real configuration.
    def guard_overwrite!(app_root, opts)
      return if opts[:force]
      existing = ['config/docker/deploy.json', 'config/deploy.json'].find do |rel|
        File.file?(File.join(app_root, rel))
      end
      return unless existing
      raise Error.new(
        "#{existing} already exists",
        expected: 'no existing deploy.json in a new project',
        current: "#{existing} present in #{app_root}",
        need: 'avoid clobbering a real config',
        fix: "lux docker:prepare --force  # to regenerate from scratch, or edit #{existing} by hand",
        category: :preflight
      )
    end

    # Build a small hash of useful signals about the project. Keeps the
    # prompt grounded in real files so the LLM doesn't invent service
    # names or base images.
    def collect_hints(app_root)
      {
        procfile: parse_procfile(app_root),
        gemfile: File.file?(File.join(app_root, 'Gemfile')),
        package_json: File.file?(File.join(app_root, 'package.json')),
        ruby_version: read_ruby_version(app_root),
        dockerfile_exists: File.file?(File.join(app_root, 'config/docker/Dockerfile')),
        compose_exists: File.file?(File.join(app_root, 'config/docker/compose.yml'))
      }
    end

    def parse_procfile(app_root)
      path = File.join(app_root, 'Procfile')
      return { exists: false, services: [] } unless File.file?(path)
      services = File.read(path).each_line.map do |line|
        line = line.chomp.strip
        next nil if line.empty? || line.start_with?('#')
        name, cmd = line.split(':', 2)
        next nil unless name && cmd
        { name: name.strip, cmd: cmd.strip }
      end.compact
      { exists: true, services: services }
    end

    def read_ruby_version(app_root)
      [
        '.ruby-version',
        '.tool-versions'
      ].each do |rel|
        path = File.join(app_root, rel)
        next unless File.file?(path)
        File.read(path).each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')
          # .tool-versions lines look like: "ruby 4.0.4"
          return Regexp.last_match(1) if line =~ /\A(?:ruby\s+)?(\d+(?:\.\d+){0,2})/
        end
      end
      nil
    end

    def command_exists?(name)
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
        File.executable?(File.join(dir, name))
      end
    end

    def build_prompt(app_root:, hints:)
      procfile = hints[:procfile]
      services_block =
        if procfile[:exists] && !procfile[:services].empty?
          "Procfile (treat each line as one logical service):\n\n" +
            procfile[:services].map { |s| "* `#{s[:name]}`: `#{s[:cmd]}`" }.join("\n")
        elsif procfile[:exists]
          'A `Procfile` exists at the project root but parses to zero services. Ask the operator which services to set up before writing anything.'
        else
          'No `Procfile` found. Ask the operator which services exist (web, job, socket, admin, ...) before writing anything.'
        end

      ruby_hint = hints[:ruby_version] ? "Ruby version pinned to `#{hints[:ruby_version]}` (use this in the Dockerfile base image)." : 'No `.ruby-version` or `.tool-versions` found; ask the operator which Ruby version to use.'

      overwrite_warning =
        if hints[:dockerfile_exists] || hints[:compose_exists]
          existing = []
          existing << '`config/docker/Dockerfile`' if hints[:dockerfile_exists]
          existing << '`config/docker/compose.yml`' if hints[:compose_exists]
          "These files already exist: #{existing.join(', ')}. Propose a diff and confirm before overwriting."
        else
          'None of the target files exist yet; create them from scratch.'
        end

      <<~PROMPT
        # Bootstrap Docker artifacts for the lux-fw `docker` plugin

        You are working inside a Lux Ruby app at `#{app_root}`.
        Goal: produce three files so `lux docker:run` and `lux docker:server:deploy` work.

        ## Project signals

        * #{ruby_hint}
        * Has `Gemfile`: #{hints[:gemfile]}
        * Has `package.json`: #{hints[:package_json]}
        * #{overwrite_warning}

        #{services_block}

        ## Files to create / propose

        1. `config/docker/Dockerfile` - multistage (base / builder / runtime),
           non-root `app` user, `WORKDIR /app`. Default `CMD` boots the web
           service; other compose services override `command:`.

        2. `config/docker/compose.yml` - one service block per logical
           service (the Procfile entries above, or whatever the operator
           confirms). Each service:
             * `image: ${<SVC>_IMAGE}` (uppercase service key)
             * `build: { context: ${LUX_SOURCE_DIR:-../..}, dockerfile: config/docker/Dockerfile }`
             * `env_file: ["${LUX_RUNTIME_ENV_FILE:-../../.env}"]`
             * bind-mount `${LUX_LOG_DIR:-../../log}:/app/log` and
               `${LUX_TMP_DIR:-../../tmp}:/app/tmp`
             * HTTP services publish `127.0.0.1:${<SVC>_PORT:-3000}:3000`
             * `restart: unless-stopped`

        3. `config/docker/deploy.json` - **must** follow the schema below.
           Do NOT include any "locked" keys. Omit "defaulted" keys unless
           you're actually overriding the default.

        --- BEGIN SCHEMA ---
        #{LuxDocker::SCHEMA}
        --- END SCHEMA ---

        ## What this plugin sets at compose runtime (so your compose.yml
        can reference them as `${VAR}`)

        * `LUX_RUNTIME_ENV_FILE` - the `.env` to load into containers
        * `LUX_LOG_DIR`, `LUX_TMP_DIR` - bind mount targets
        * `LUX_SOURCE_DIR` - app root locally; on the remote, the synced app dir
        * `<SVC>_IMAGE` - resolved image ref per service
        * `<SVC>_PORT` - resolved host port (loopback only)

        ## Rules

        * Ask the operator before assuming: domain names, Postgres URL,
          whether to include a `compose.staging.yml`, whether to enable
          a `tls` block (wildcards only).
        * Never invent service names not in the Procfile (or that the
          operator confirms).
        * Never write a `deploy.json` with locked keys (root, compose,
          image_tag, images). The validator will reject the file.
        * Don't add a `tls` block unless the operator wants wildcard certs.
      PROMPT
    end
  end

  module Commands
    module_function

    # Top-level entry: `lux docker:prepare`.
    def prepare(_profile, opts = {})
      Prepare.run(opts)
    end
  end
end
