require 'etc'
require 'yaml'

module LuxDocker
  module Config
    APP_RE ||= /\A[a-z][a-z0-9_-]{0,62}\z/
    SERVER_RE ||= /\A[A-Za-z0-9._@:\[\]-]+\z/
    DOMAIN_RE ||= /\A(\*\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/
    ENV_KEY_RE ||= /\A[A-Z_][A-Z0-9_]*\z/
    # Caddy DNS provider modules we know how to render. Extend by adding the
    # provider name here AND ensuring the host Caddy build includes
    # github.com/caddy-dns/<name>. See KNOWLEDGE.md for the xcaddy recipe.
    TLS_DNS_PROVIDERS ||= %w[cloudflare].freeze
    # POSIX-ish system username: lowercase or underscore start, then [a-z0-9_-].
    SERVICE_USER_RE ||= /\A[a-z_][a-z0-9_-]{0,31}\z/
    # Logical service key in `services:` and `images:` (also matches compose svc name).
    # Hyphens disallowed: generated compose env vars (`<SVC>_IMAGE`, `<SVC>_PORT`)
    # must be valid shell identifiers, and `${WEB-API_IMAGE}` is parsed as a
    # Bash-style default expansion, not a variable name.
    SERVICE_NAME_RE ||= /\A[a-z][a-z0-9_]{0,30}\z/
    # Docker image reference: [registry-host[:port]/]name[:tag], names are
    # lowercase. The optional leading `host[:port]/` lets self-hosted
    # registries on non-default ports validate.
    IMAGE_RE ||= /\A([a-z0-9][a-z0-9.-]*(:[0-9]+)?\/)?[a-z0-9][a-z0-9._\/-]{0,127}(:[A-Za-z0-9_.-]{1,127})?\z/
    # Image tag suitable for docker tags
    IMAGE_TAG_RE ||= /\A[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}\z/
    # Compose project name and matching apps-root path component
    PROJECT_RE ||= /\A[a-z0-9][a-z0-9_-]{0,62}\z/
    # Apps root on the host is fixed: <service_user>'s home + /lux-apps.
    # Not configurable in deploy.json - keeps the path predictable across
    # apps on the same host. Caddy needs `x` on the home dir to traverse
    # symlinks; ensure_remote_layout! chmods it 0755 once.
    SECRET_GEN_TOKEN ||= '$generate'.freeze
    # Default service user that owns app files on the host. Override in
    # deploy.json or via --service-user; if neither is set this is used.
    SERVICE_USER ||= 'deployer'.freeze

    module_function

    def resolve(profile, opts = {})
      profile = profile.to_s.empty? ? 'default' : profile.to_s
      app_root = find_app_root(Dir.pwd)
      config_path = resolve_config_path(opts, app_root)

      unless File.file?(config_path)
        default_target = File.join(app_root, 'config/docker/deploy.json')
        raise Error.new(
          'deploy config not found',
          expected: "#{default_target} (or config/deploy.json) exists",
          current: "missing #{config_path}",
          need: 'create a deploy config or pass --config PATH',
          fix: "cp #{LuxDocker.plugin_root.join('templates/deploy.json.example')} #{default_target}",
          category: :preflight
        )
      end

      data = JSON.parse(File.read(config_path))
      raw = resolve_profile(data, profile)
      reject_locked_keys!(raw)
      raw = deep_merge(raw, cli_overlay(opts))

      # Precedence: --app CLI > profile "app" > cwd basename.
      app = (opts[:app] || raw['app'] || default_app_name(opts, app_root)).to_s
      raw['app'] = app
      raw['profile'] = profile
      raw['app_root'] = app_root
      raw['config_path'] = config_path
      raw['env'] ||= {}
      raw['services'] ||= {}
      raw['healthcheck_defaults'] ||= {
        'path' => '/',
        'timeout' => 30,
        'expect_status' => [200, 201, 204, 301, 302]
      }
      # `image_tag` is auto-derived (git SHA, falling back to "latest") and
      # only overrideable via --image-tag at the CLI. compose + images fall
      # out of conventions and the services map - see derive_*! below.
      raw['image_tag'] = derive_image_tag(opts, app_root)
      # Local-test mode (set by `docker:run`): per-render flag that flips
      # `{{service_user}}` to the OS user invoking lux, so DB_URLs like
      # `postgresql://{{service_user}}@{{host}}/...` connect as `dux` locally
      # and as `deployer` on the deployed server. Stripped from `normalized`
      # before return so downstream code never sees it.
      raw['_local_test'] = true if opts[:local_test]

      load_lux_env(app_root) if contains_config_placeholder?(raw)
      resolved = interpolate(raw, raw)
      env_resolved = interpolate_env_refs(resolved)
      normalized = symbolize(env_resolved)
      normalized.delete(:_local_test)

      normalized[:app_underscored] = normalized[:app].tr('-', '_')
      normalized[:env] ||= {}
      normalized[:user] = ssh_user_hint(normalized[:server])
      normalized[:service_user] ||= SERVICE_USER
      normalized[:compose_project] ||= "lux-#{normalized[:app]}"
      # Root and path are fully derived from service_user and app.
      normalized[:root] = "/home/#{normalized[:service_user]}/lux-apps"
      normalized[:path] = "#{normalized[:root]}/#{normalized[:app]}"
      normalized[:basic_auth] = opts[:basic_auth] if opts.key?(:basic_auth)
      normalized[:compose] = derive_compose(profile, app_root)
      normalized[:images] = derive_images(normalized)

      validate!(normalized)
      normalized
    rescue JSON::ParserError => e
      raise Error.new(
        'deploy config is invalid JSON',
        expected: "#{config_path} parses as JSON",
        current: e.message,
        need: 'fix deploy.json syntax',
        fix: config_path.to_s,
        category: :preflight
      )
    end

    # Locate deploy.json. Preferred location is config/docker/deploy.json (kept
    # alongside compose.yml and Dockerfile). Falls back to the legacy
    # config/deploy.json so existing apps keep working.
    def resolve_config_path(opts, app_root)
      return File.expand_path(opts[:config]) if opts[:config]
      preferred = File.join(app_root, 'config/docker/deploy.json')
      return preferred if File.file?(preferred)
      legacy = File.join(app_root, 'config/deploy.json')
      return legacy if File.file?(legacy)
      preferred
    end

    def find_app_root(start)
      path = Pathname.new(start).expand_path
      loop do
        config_dir = path.join('config')
        return path.to_s if config_dir.join('config.yaml').file? || config_dir.join('environment.rb').file? || config_dir.join('env.rb').file?
        break if path.root?
        path = path.parent
      end

      raise Error.new(
        'no Lux app root found in cwd or parents',
        expected: 'config/config.yaml or config/environment.rb in cwd or a parent directory',
        current: "started at #{start}",
        need: 'run from a Lux app or pass --config from an app checkout',
        fix: 'cd /path/to/lux/app',
        category: :preflight
      )
    end

    def default_app_name(_opts, _app_root)
      File.basename(Dir.pwd)
    end

    def resolve_profile(data, profile, seen = [])
      block = data[profile]
      unless block
        raise Error.new(
          'deploy profile not found',
          expected: "profile #{profile.inspect} in deploy.json",
          current: "available profiles: #{data.keys.join(', ')}",
          need: 'choose an existing profile or add one',
          fix: 'edit config/deploy.json',
          category: :preflight
        )
      end

      if profile == 'default'
        parent = {}
      else
        parent_name = block.fetch('extends', 'default')
        if seen.include?(parent_name)
          raise Error.new(
            'deploy profile extends cycle',
            expected: 'extends chain terminates at default',
            current: (seen + [parent_name]).join(' -> '),
            need: 'remove the cycle in deploy.json',
            fix: 'edit config/deploy.json',
            category: :preflight
          )
        end
        parent = resolve_profile(data, parent_name, seen + [profile])
      end

      deep_merge(parent, block.reject { |k, _| k == 'extends' })
    end

    # Keys that the plugin owns by convention and refuses to read from
    # deploy.json. Flagging them loudly beats silently overriding -
    # otherwise users wonder why their setting "doesn't work".
    LOCKED_KEYS ||= {
      'root' => 'apps root is fixed at /home/<service_user>/lux-apps',
      'compose' => 'compose files auto-detected: config/docker/compose.yml + compose.<profile>.yml if present',
      'image_tag' => 'derived from `git rev-parse --short HEAD`; override per-call with --image-tag',
      'images' => 'derived from services map: each service `web` gets image `<app>-web:<image_tag>`'
    }.freeze

    def reject_locked_keys!(raw)
      LOCKED_KEYS.each do |key, why|
        next unless raw.key?(key)
        raise Error.new(
          "`#{key}` is not configurable in deploy.json",
          expected: "no `#{key}` key in any profile",
          current: "#{key}=#{raw[key].inspect}",
          need: why,
          fix: "remove the \"#{key}\" key from config/docker/deploy.json",
          category: :preflight
        )
      end
    end

    # Auto-detect compose files: always start with config/docker/compose.yml,
    # then layer on config/docker/compose.<profile>.yml if the profile-
    # specific file exists. Keeps multi-profile setups boilerplate-free.
    def derive_compose(profile, app_root)
      base = 'config/docker/compose.yml'
      extra = "config/docker/compose.#{profile}.yml"
      paths = [base]
      paths << extra if File.file?(File.join(app_root, extra))
      paths
    end

    # Derive a deterministic image_tag: short git SHA from the app's repo,
    # CLI --image-tag override wins, "latest" as last-resort fallback for
    # apps that aren't in a git checkout.
    def derive_image_tag(opts, app_root)
      return opts[:image_tag].to_s if opts[:image_tag] && !opts[:image_tag].to_s.empty?
      result = nil
      Dir.chdir(app_root) do
        out = `git rev-parse --short HEAD 2>/dev/null`.strip
        result = out unless out.empty?
      end
      result || 'latest'
    end

    # Convention: every service `<svc>` gets image `<app>-<svc>:<image_tag>`.
    # Compose builds tag images as `<project>-<svc>` by default; Image.build!
    # retags them to these refs and ships them under those names.
    def derive_images(normalized)
      normalized[:services].each_with_object({}) do |(name, _spec), out|
        out[name] = "#{normalized[:app]}-#{name}:#{normalized[:image_tag]}"
      end
    end

    def cli_overlay(opts)
      overlay = {}
      %i[server image_tag service_user].each do |key|
        overlay[key.to_s] = opts[key] if opts.key?(key) && !opts[key].nil?
      end
      env = parse_env_opts(opts[:env])
      overlay['env'] = env if env.any?
      overlay
    end

    def parse_env_opts(value)
      Array(value).compact.each_with_object({}) do |entry, hash|
        entry.to_s.split(',').each do |part|
          next if part.empty?
          key, val = part.split('=', 2)
          hash[key] = val.nil? ? true : val
        end
      end
    end

    def deep_merge(a, b)
      a = a || {}
      b = b || {}
      a.merge(b) do |_key, old, new|
        old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new
      end
    end

    def contains_config_placeholder?(value)
      case value
      when Hash then value.any? { |_, v| contains_config_placeholder?(v) }
      when Array then value.any? { |v| contains_config_placeholder?(v) }
      when String then value.include?('{{config.')
      else false
      end
    end

    def load_lux_env(app_root)
      env_file = File.join(app_root, 'config/env.rb')
      environment_file = File.join(app_root, 'config/environment.rb')
      file = File.file?(env_file) ? env_file : environment_file
      Dir.chdir(app_root) { require file }
    rescue LoadError => e
      raise Error.new(
        'cannot load Lux config for deploy interpolation',
        expected: "#{file} loads successfully",
        current: e.message,
        need: '{{config.*}} interpolation requires the app environment',
        fix: file.to_s,
        category: :preflight
      )
    end

    def interpolate(value, root)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k] = interpolate(v, root) }
      when Array
        value.map { |v| interpolate(v, root) }
      when String
        previous = nil
        current = value.dup
        until current == previous
          previous = current
          current = current.gsub(/\{\{([^}]+)\}\}/) do
            key = Regexp.last_match(1).strip
            # Defer env.* resolution to a later pass so generated/required
            # values from the env block can flow through.
            key.start_with?('env.') ? Regexp.last_match(0) : lookup_placeholder(key, root)
          end
        end
        current
      else
        value
      end
    end

    # Second pass: only after env values are known, expand {{env.KEY}} refs.
    # Called from EnvFile.resolved_env so we can resolve required/$generate
    # values first, then thread them into downstream config values.
    def interpolate_env_refs(value, lookup = nil)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k] = interpolate_env_refs(v, lookup) }
      when Array
        value.map { |v| interpolate_env_refs(v, lookup) }
      when String
        value.gsub(/\{\{env\.([A-Z_][A-Z0-9_]*)\}\}/) do
          key = Regexp.last_match(1)
          lookup ? lookup.call(key) : Regexp.last_match(0)
        end
      else
        value
      end
    end

    def lookup_placeholder(key, root)
      case key
      when 'app'
        root['app'].to_s
      when 'app_underscored'
        root['app'].to_s.tr('-', '_')
      when 'profile'
        root['profile'].to_s
      when 'image_tag'
        root['image_tag'].to_s
      when 'host'
        # Address a container uses to reach a service running on the host
        # (e.g. host-side postgres). Not the public/SSH target - that is
        # the profile's `server` field.
        #
        # Resolves to `host.docker.internal`, which is portable across
        # Docker Desktop (Mac/Windows, built-in) and Linux (where compose
        # must declare `extra_hosts: ["host.docker.internal:host-gateway"]`
        # per service). Compose.ensure_host_gateway_mapping! enforces that
        # mapping in preflight so this placeholder never produces a dead
        # hostname on Linux.
        'host.docker.internal'
      when 'service_user'
        # OS user the container effectively runs as for host-side resource
        # access (chiefly DB roles): the local OS user during `docker:run`
        # rendering, the configured `service_user` (default `deployer`)
        # during deploy. Lets a single `deploy.json` such as
        #   "DB_URL": "postgresql://{{service_user}}@{{host}}/myapp"
        # work both locally (connects as `dux`) and remotely (connects as
        # `deployer`) without per-env overrides - operators just grant
        # each user a matching Postgres role.
        if root['_local_test']
          (ENV['USER'] || Etc.getlogin || SERVICE_USER).to_s
        else
          (root['service_user'] || SERVICE_USER).to_s
        end
      when /\Aconfig\.(.+)/
        parts = Regexp.last_match(1).split('.')
        val = lux_config_value(parts)
        unless val.is_a?(String) || val.is_a?(Numeric) || val == true || val == false
          raise Error.new(
            "unresolved {{config.#{parts.join('.')}}} in deploy.json",
            expected: "Lux.config.dig(#{parts.map(&:inspect).join(', ')}) returns a scalar",
            current: val.nil? ? 'nil' : val.class.to_s,
            need: 'set the config key to a scalar value',
            fix: 'edit config/config.yaml',
            category: :preflight
          )
        end
        val.to_s
      else
        raise Error.new(
          'unsupported placeholder in deploy config',
          expected: '{{app}}, {{app_underscored}}, {{profile}}, {{image_tag}}, {{host}}, {{service_user}}, {{config.*}}, or {{env.KEY}}',
          current: "{{#{key}}}",
          need: 'use a supported deploy placeholder',
          fix: root['config_path'].to_s,
          category: :preflight
        )
      end
    end

    def lux_config_value(parts)
      cur = Lux.config
      parts.each do |part|
        if cur.respond_to?(:dig)
          cur = cur[part] || cur[part.to_sym]
        else
          cur = cur.public_send(part)
        end
        break if cur.nil?
      end
      cur
    end

    def symbolize(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize(v) }
      when Array
        value.map { |v| symbolize(v) }
      else
        value
      end
    end

    def ssh_user_hint(server)
      server.to_s.include?('@') ? server.to_s.split('@', 2).first : Etc.getlogin || ENV['USER'] || 'deploy'
    end

    def validate!(config)
      validate_match(:app, config[:app], APP_RE)
      validate_match(:server, config[:server], SERVER_RE)
      validate_match(:service_user, config[:service_user], SERVICE_USER_RE)
      validate_match(:image_tag, config[:image_tag], IMAGE_TAG_RE)
      validate_match(:compose_project, config[:compose_project], PROJECT_RE)
      validate_path(config[:root])
      validate_path(config[:path])
      validate_compose(config[:compose], config[:app_root])
      validate_compose_host_gateway(config[:compose], config[:app_root])
      # services first: image keys are auto-derived from service keys, so a
      # bad service name should surface as `service_name`, not `image_key`.
      validate_services(config[:services])
      validate_images(config[:images])
      validate_domain_uniqueness(config[:services])
      validate_port_uniqueness(config[:services])
      validate_env(config[:env])
      validate_tls(config)
      true
    end

    # The `tls` profile block is optional but mandatory when any service uses
    # a wildcard domain - HTTP-01 / TLS-ALPN-01 cannot issue `*.example.com`.
    # Shape: { dns_provider: "cloudflare", <either api_token OR api_token_env> }.
    #   * api_token_env: NAME of an env var (recommended for shared repos)
    #   * api_token:     literal token value (single-dev convenience)
    # Exactly one of the two must be set.
    def validate_tls(config)
      tls = config[:tls]
      wildcard = wildcard_domain(config[:services])

      if tls.nil? || tls.empty?
        return unless wildcard
        validation_error(
          'wildcard domain requires tls.dns_provider',
          'tls block configured when any services.*.domains contains a wildcard',
          "wildcard #{wildcard} present, tls block missing",
          'add a tls block to the profile (see deploy.json.example)',
          'edit config/docker/deploy.json tls block'
        )
      end

      unless tls.is_a?(Hash)
        validation_error('invalid tls block', 'tls is an object', tls.inspect, 'provide { dns_provider, api_token | api_token_env }', 'edit config/docker/deploy.json tls block')
      end

      provider = tls[:dns_provider].to_s
      unless TLS_DNS_PROVIDERS.include?(provider)
        validation_error('unsupported tls.dns_provider', "tls.dns_provider in #{TLS_DNS_PROVIDERS.inspect}", "tls.dns_provider=#{provider.inspect}", 'use a supported DNS provider', 'edit config/docker/deploy.json tls.dns_provider')
      end

      has_literal = !tls[:api_token].to_s.empty?
      has_env_ref = !tls[:api_token_env].to_s.empty?

      if has_literal && has_env_ref
        validation_error('tls accepts only one of api_token / api_token_env', 'exactly one is set', 'both are set', 'pick one', 'edit config/docker/deploy.json tls block')
      end
      unless has_literal || has_env_ref
        validation_error('tls requires api_token or api_token_env', 'one of the two is set', 'neither is set', 'pick one', 'edit config/docker/deploy.json tls block')
      end

      if has_env_ref
        token_env = tls[:api_token_env].to_s
        unless token_env.match?(ENV_KEY_RE)
          validation_error('invalid tls.api_token_env', "tls.api_token_env matches #{ENV_KEY_RE.inspect}", "tls.api_token_env=#{token_env.inspect}", 'name the env var that holds the DNS API token (or use api_token for a literal value)', 'edit config/docker/deploy.json tls.api_token_env')
        end
        token = ENV[token_env]
        if token.nil? || token.empty?
          validation_error(
            'tls.api_token_env not set in caller environment',
            "#{token_env} exported locally before deploy",
            "#{token_env} unset",
            'export the DNS API token before running deploy',
            "export #{token_env}=..."
          )
        end
      end

      tls[:dns_provider] = provider
      # Normalize to a single internal env-var key Caddy can reference. When
      # the user gave a literal token, generate a deterministic var name we
      # plant into /etc/caddy/caddy.env at install time.
      tls[:_caddy_env_key] = has_env_ref ? tls[:api_token_env].to_s : "LUX_TLS_DNS_TOKEN_#{provider.upcase}"
    end

    def wildcard_domain(services)
      services.each do |_name, spec|
        Array(spec[:domains]).each { |d| return d if d.to_s.start_with?('*.') }
      end
      nil
    end

    def validate_compose(value, app_root)
      unless value.is_a?(Array) && !value.empty?
        validation_error('invalid compose list', 'compose is a non-empty array of paths', value.inspect, 'declare at least one compose file', 'edit config/deploy.json compose block')
      end
      value.each do |path|
        unless path.is_a?(String) && !path.empty? && !path.include?('..')
          validation_error('invalid compose path', 'compose entry is a relative path with no ..', path.inspect, 'use a relative path like config/docker/compose.yml', "edit config/deploy.json compose entry #{path.inspect}")
        end
        full = File.expand_path(path, app_root)
        unless File.file?(full)
          validation_error('compose file missing', "#{full} exists", "no such file: #{full}", "create the compose file or fix the path", "ls #{full}")
        end
      end
    end

    # Every compose service must declare the `host.docker.internal:host-gateway`
    # extra_hosts mapping. Without it `{{host}}` -> `host.docker.internal`
    # resolves only on Docker Desktop (Mac/Windows) and silently fails on Linux.
    # We treat the mapping as mandatory so the same compose works in local test
    # (`docker:run`) and on the Linux deploy target.
    HOST_GATEWAY_MAPPING ||= 'host.docker.internal:host-gateway'.freeze

    def validate_compose_host_gateway(compose_files, app_root)
      missing = []
      Array(compose_files).each do |rel|
        full = File.expand_path(rel, app_root)
        services = load_compose_services(full)
        next if services.nil?
        services.each do |name, spec|
          next unless spec.is_a?(Hash)
          entries = Array(spec['extra_hosts']).map { |e| e.is_a?(String) ? e.strip : nil }.compact
          missing << "#{rel}:services.#{name}" unless entries.include?(HOST_GATEWAY_MAPPING)
        end
      end
      return if missing.empty?
      validation_error(
        'compose service missing host.docker.internal:host-gateway mapping',
        "every service declares extra_hosts: [\"#{HOST_GATEWAY_MAPPING}\"]",
        "missing on: #{missing.join(', ')}",
        'add the extra_hosts mapping so `{{host}}` (host.docker.internal) resolves on Linux too',
        'edit the listed compose file(s) and add: extra_hosts: ["host.docker.internal:host-gateway"]'
      )
    end

    def load_compose_services(full)
      raw = YAML.safe_load(File.read(full), aliases: true, permitted_classes: [])
      return nil unless raw.is_a?(Hash)
      services = raw['services']
      services.is_a?(Hash) ? services : nil
    rescue Psych::SyntaxError => e
      validation_error(
        'compose file is not valid YAML',
        "#{full} parses as YAML",
        e.message,
        'fix the compose file syntax',
        "edit #{full}"
      )
    end

    def validate_images(images)
      unless images.is_a?(Hash)
        validation_error('invalid images', 'images is a map of service_key -> image_ref', images.inspect, 'declare images per service', 'edit config/deploy.json images block')
      end
      images.each do |name, ref|
        validate_match(:image_key, name, SERVICE_NAME_RE)
        unless ref.is_a?(String) && ref.match?(IMAGE_RE)
          validation_error('invalid image ref', "images.#{name} matches #{IMAGE_RE.inspect}", "images.#{name}=#{ref.inspect}", 'provide a valid docker image reference', "edit config/deploy.json images.#{name}")
        end
      end
    end

    def validate_services(services)
      unless services.is_a?(Hash) && !services.empty?
        validation_error('invalid services', 'services is a non-empty map', services.inspect, 'declare at least one service', 'edit config/deploy.json services block')
      end
      services.each do |name, spec|
        validate_match(:service_name, name, SERVICE_NAME_RE)
        unless spec.is_a?(Hash)
          validation_error("invalid service #{name}", "service entry is an object", spec.inspect, 'provide { compose_service, host_port, domains, ... }', "edit services.#{name}")
        end
        compose_service = spec[:compose_service] || spec['compose_service'] || name.to_s
        spec[:compose_service] = compose_service.to_s
        validate_match(:compose_service, spec[:compose_service], SERVICE_NAME_RE)
        validate_host_port(name, spec)
        validate_domains(name, spec)
        validate_healthcheck(name, spec)
      end
    end

    def validate_host_port(name, spec)
      port = spec[:host_port] || spec['host_port']
      if port.nil?
        spec[:host_port] = nil
        range = spec[:port_range] || spec['port_range']
        unless range.is_a?(Array) && range.length == 2 && range.all? { |v| v.is_a?(Integer) && v.between?(1024, 65_535) } && range[0] <= range[1]
          validation_error("invalid port_range for #{name}", 'port_range is [lo,hi] within 1024..65535', range.inspect, 'provide a port_range or set host_port explicitly', "edit services.#{name}.port_range")
        end
        spec[:port_range] = range.map(&:to_i)
      else
        port = port.to_i
        unless port.between?(1024, 65_535)
          validation_error("invalid host_port for #{name}", 'host_port is in 1024..65535', port.inspect, 'pick an unprivileged port', "edit services.#{name}.host_port")
        end
        spec[:host_port] = port
      end
      cp = spec[:container_port] || spec['container_port']
      spec[:container_port] = cp.to_i if cp
    end

    def validate_domains(name, spec)
      domains = Array(spec[:domains] || spec['domains'])
      if domains.empty?
        validation_error("missing domains for #{name}", "services.#{name}.domains is a non-empty array", domains.inspect, 'declare at least one domain', "edit services.#{name}.domains")
      end
      domains.each do |domain|
        unless domain.is_a?(String) && domain.match?(DOMAIN_RE)
          validation_error('invalid domain', 'each domain matches DNS naming rules', "domain=#{domain.inspect}", 'provide DNS-safe lowercase domains', "edit services.#{name}.domains")
        end
      end
      spec[:domains] = domains
    end

    def validate_healthcheck(_name, spec)
      hc = spec[:healthcheck] || spec['healthcheck']
      return if hc.nil?
      unless hc.is_a?(Hash)
        validation_error('invalid healthcheck', 'healthcheck is an object', hc.inspect, 'provide { path, expect_status }', 'edit services.*.healthcheck')
      end
      path = (hc[:path] || hc['path']).to_s
      unless path.start_with?('/') && !path.match?(/[\s;&|`$<>\\]/)
        validation_error('invalid healthcheck path', 'path starts with / and has no shell metacharacters', path.inspect, 'provide a safe HTTP path', 'edit healthcheck.path')
      end
      hc[:path] = path
      statuses = Array(hc[:expect_status] || hc['expect_status']).map(&:to_i)
      statuses = [200, 201, 204, 301, 302] if statuses.empty?
      hc[:expect_status] = statuses
      hc[:timeout] = (hc[:timeout] || hc['timeout'] || 30).to_i
      spec[:healthcheck] = hc
    end

    def validate_domain_uniqueness(services)
      seen = {}
      services.each do |name, spec|
        Array(spec[:domains]).each do |domain|
          if seen.key?(domain)
            validation_error('duplicate domain in services', 'each domain belongs to one service', "domain=#{domain} is on services.#{seen[domain]} and services.#{name}", 'remove the duplicate', "edit services.#{name}.domains")
          end
          seen[domain] = name
        end
      end
    end

    def validate_port_uniqueness(services)
      seen = {}
      services.each do |name, spec|
        port = spec[:host_port]
        next if port.nil?
        if seen.key?(port)
          validation_error('duplicate host_port', 'each service uses a distinct host_port', "host_port=#{port} on services.#{seen[port]} and services.#{name}", 'choose unique ports', "edit services.#{name}.host_port")
        end
        seen[port] = name
      end
    end

    def validate_path(path)
      ok = path.to_s.start_with?('/') && !path.to_s.include?('..') && !path.to_s.match?(/[\s;&|`$<>\\]/)
      validation_error('invalid path', 'absolute path with no spaces, .., or shell metacharacters', "path=#{path.inspect}", 'provide a safe absolute deploy path', 'pass --root /srv/lux-apps') unless ok
    end

    def validate_env(env)
      env.each do |key, value|
        validate_match(:env_key, key, ENV_KEY_RE)
        if value.is_a?(String) && value.include?("\0")
          validation_error('invalid env value', 'env values contain no embedded NUL', "#{key} contains NUL", 'remove NUL bytes from env value', "edit env #{key}")
        end
      end
    end

    def validate_match(name, value, regex)
      unless value.to_s.match?(regex)
        validation_error(
          "invalid #{name}",
          "#{name} matches #{regex.inspect}",
          "#{name}=#{value.inspect}",
          "provide a valid #{name}",
          "edit config/deploy.json or pass --#{name.to_s.tr('_', '-')} VALUE"
        )
      end
    end

    def validation_error(summary, expected, current, need, fix)
      raise Error.new(summary, expected: expected, current: current, need: need, fix: fix, category: :preflight)
    end
  end
end
