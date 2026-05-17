require 'erb'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'securerandom'
require 'tmpdir'
require 'shellwords'
require 'time'

module LuxDeploy
  ROOT ||= Pathname.new(File.expand_path('..', __dir__))

  EXIT_CODES ||= {
    preflight: 10,
    source: 20,
    compose: 40,
    caddy: 50,
    healthcheck: 60,
    unknown: 99
  }

  class Error < StandardError
    attr_reader :summary, :expected, :current, :need, :fix, :category

    def initialize(summary, expected:, current:, need:, fix:, category: :unknown)
      @summary = summary
      @expected = expected
      @current = current
      @need = need
      @fix = fix
      @category = category
      super(summary)
    end

    def code
      EXIT_CODES.fetch(category, EXIT_CODES[:unknown])
    end

    def to_s
      [
        "ERROR: #{summary}",
        "  expected: #{expected}",
        "  current:  #{current}",
        "  need:     #{need}",
        "  fix:      #{fix}"
      ].join("\n")
    end
  end

  class CommandError < Error
    attr_reader :result

    def initialize(summary, result, expected:, need:, fix:, category: :unknown)
      @result = result
      current = "exit #{result.status}"
      current += ", stdout #{result.stdout.inspect}" unless result.stdout.to_s.empty?
      current += ", stderr #{result.stderr.inspect}" unless result.stderr.to_s.empty?
      super(summary, expected: expected, current: current, need: need, fix: fix, category: category)
    end
  end

  Result = Struct.new(:cmd, :stdout, :stderr, :status, keyword_init: true) do
    def success?
      status == 0
    end
  end

  class Context
    attr_reader :config, :ssh, :options, :started_at
    attr_accessor :remote_user, :resolved_env

    def initialize(config, options)
      @config = config
      @options = options
      @started_at = Time.now.utc
      @ssh = SSH.new(config, dry_run: options[:dry_run], quiet: options[:quiet])
      @remote_user = config[:user]
      @resolved_env = {}
    end

    def service_user
      config[:service_user]
    end

    def app
      config[:app]
    end

    def path
      config[:path]
    end

    def dry_run?
      options[:dry_run]
    end

    def quiet?
      options[:quiet]
    end

    def say(message)
      puts message unless quiet?
    end

    def step(message)
      say "deploy: #{message}"
    end
  end

  module_function

  def plugin_root
    ROOT
  end

  def require_support!
    require_relative 'lux_deploy_config'
    require_relative 'lux_deploy_ssh'
    require_relative 'lux_deploy_compose'
    require_relative 'lux_deploy_image'
    require_relative 'lux_deploy_caddy'
    require_relative 'lux_deploy_manifest'
    require_relative 'lux_deploy_slot'
    require_relative 'lux_deploy_llm_prepare'
  end

  def run_local(cmd, dry_run: false, quiet: false, input: nil)
    puts "+ #{cmd}" unless quiet
    return Result.new(cmd: cmd, stdout: '', stderr: '', status: 0) if dry_run

    stdout, stderr, status = Open3.capture3(cmd, stdin_data: input)
    Result.new(cmd: cmd, stdout: stdout.strip, stderr: stderr.strip, status: status.exitstatus)
  end

  def run_local!(cmd, **opts)
    result = run_local(cmd, **opts)
    return result if result.success?

    raise CommandError.new(
      'local command failed',
      result,
      expected: "#{cmd.inspect} exits 0",
      need: 'local command succeeds',
      fix: cmd,
      category: :unknown
    )
  end

  def sh(value)
    Shellwords.escape(value.to_s)
  end

  def sq(value)
    Shellwords.escape(value.to_s)
  end

  def now_ts
    Time.now.utc.strftime('%Y-%m-%d-%H-%M-%S')
  end

  def iso_now
    Time.now.utc.iso8601
  end

  def duration_since(time)
    (Time.now.utc - time).round
  end

  def as_service_user(ctx, cmd)
    return cmd if ctx.remote_user == ctx.service_user
    "sudo -u #{sh(ctx.service_user)} -H bash -lc #{sq(cmd)}"
  end

  def render_template(name, vars)
    path = plugin_root.join('templates', name)
    ERB.new(path.read, trim_mode: '-').result_with_hash(vars)
  end

  def handle_cli_error(error, quiet: false)
    if error.is_a?(LuxDeploy::Error)
      warn error.to_s
      exit error.code
    end

    wrapped = Error.new(
      error.message,
      expected: 'command completes without an unhandled exception',
      current: "#{error.class}: #{error.message}",
      need: 'inspect the stack trace and fix the deploy plugin or input',
      fix: 'rerun with RUBYOPT=-d for debug output',
      category: :unknown
    )
    warn wrapped.to_s
    warn error.backtrace.join("\n") unless quiet
    exit wrapped.code
  end
end

LuxDeploy.require_support!

module LuxDeploy
  # EnvFile resolves config[:env] into the remote shared/.env file. Source
  # of truth is deploy.json's `env:` block; the file is rewritten each
  # deploy. `$generate` reads or creates a stable per-app secret in the
  # remote .env so values survive across deploys.
  module EnvFile
    module_function

    def write!(ctx)
      env = ctx.config[:env]
      return if env.nil? || env.empty?

      # First pass: read existing remote .env so $generate values are stable.
      existing = read_remote(ctx)
      resolved = resolve(env, existing, ctx)
      ctx.resolved_env = resolved
      # Second pass: expand {{env.KEY}} placeholders in any string value
      # using the now-resolved env map. This also propagates back into
      # config (DB_URL etc.) for downstream consumers via interpolate_env_refs.
      lookup = ->(key) {
        unless resolved.key?(key)
          raise Error.new(
            "unresolved env.#{key} placeholder",
            expected: "env.#{key} present in resolved env block",
            current: "env.#{key} not set",
            need: "add #{key} to deploy.json env block",
            fix: "edit config/deploy.json env.#{key}",
            category: :preflight
          )
        end
        resolved[key]
      }
      expanded = resolved.each_with_object({}) do |(k, v), h|
        h[k] = v.is_a?(String) ? Config.interpolate_env_refs(v, lookup) : v
      end
      ctx.config[:env] = expanded
      ctx.config[:services] = Config.interpolate_env_refs(ctx.config[:services], lookup) if ctx.config[:services]

      content = expanded.map { |k, v| "#{k}=#{Shellwords.escape(v.to_s)}" }.join("\n") + "\n"
      cmd = [
        "printf %s #{LuxDeploy.sq(content)} > #{LuxDeploy.sh(ctx.path)}/shared/.env.next",
        "mv #{LuxDeploy.sh(ctx.path)}/shared/.env.next #{LuxDeploy.sh(ctx.path)}/shared/.env",
        "chmod 0600 #{LuxDeploy.sh(ctx.path)}/shared/.env"
      ].join(' && ')
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :preflight, summary: 'cannot write remote .env')
    end

    def resolve(env, existing, _ctx)
      env.each_with_object({}) do |(key, value), out|
        key_s = key.to_s
        case value
        when true
          local = ENV[key_s]
          if local.nil? || local.empty?
            raise Error.new(
              'required env var not set locally',
              expected: "#{key_s} present in caller's environment",
              current: "#{key_s} unset",
              need: "export #{key_s} before running deploy (declared as true in deploy.json env block)",
              fix: "export #{key_s}=VALUE",
              category: :preflight
            )
          end
          out[key_s] = local
        when false, nil
          local = ENV[key_s]
          out[key_s] = local if local
        when Config::SECRET_GEN_TOKEN
          out[key_s] = existing[key_s] || SecureRandom.hex(32)
        else
          out[key_s] = value.to_s
        end
      end
    end

    # Read the host-side shared/.env so $generate values can be reused across
    # deploys. The file is chmod 0600 and owned by service_user, so reading
    # has to run through `as_service_user`; doing a bare `cat` as a sudo
    # SSH user silently fails on permission and the existing secrets get
    # rotated on every deploy. A missing file means a fresh app (return {});
    # anything else (permission, IO error) is a hard failure.
    def read_remote(ctx)
      path = "#{LuxDeploy.sh(ctx.path)}/shared/.env"
      cmd = "if [ ! -f #{path} ]; then echo __LUX_NO_ENV__; else cat #{path}; fi"
      result = ctx.ssh.ssh(LuxDeploy.as_service_user(ctx, cmd))
      unless result.success?
        raise CommandError.new(
          'cannot read remote shared/.env',
          result,
          expected: "service_user can read #{ctx.path}/shared/.env (or file is absent)",
          need: 'preserve $generate secrets across deploys',
          fix: "ssh #{ctx.config[:server]} #{LuxDeploy.sq(LuxDeploy.as_service_user(ctx, "cat #{path}"))}",
          category: :preflight
        )
      end
      return {} if result.stdout.strip == '__LUX_NO_ENV__'

      result.stdout.each_line.each_with_object({}) do |line, out|
        line = line.chomp
        next if line.empty? || line.start_with?('#')
        k, v = line.split('=', 2)
        next unless k
        out[k] = Shellwords.split(v.to_s).first if v
      end
    end
  end

  # DeployEnv writes config/docker/deploy.env on the host so docker compose
  # can read --env-file. This file contains compose-level vars (paths, image
  # refs, ports), never runtime secrets.
  module DeployEnv
    module_function

    def write!(ctx)
      lines = []
      lines << "LUX_RUNTIME_ENV_FILE=#{ctx.path}/shared/.env"
      lines << "LUX_LOG_DIR=#{ctx.path}/shared/log"
      lines << "LUX_TMP_DIR=#{ctx.path}/shared/tmp"
      lines << "LUX_SOURCE_DIR=#{ctx.path}"
      lines << "COMPOSE_PROJECT_NAME=#{ctx.config[:compose_project]}"
      ctx.config[:images].each do |svc, ref|
        lines << "#{svc.to_s.upcase}_IMAGE=#{ref}"
      end
      ctx.config[:services].each do |name, spec|
        next unless spec[:host_port]
        lines << "#{name.to_s.upcase}_PORT=#{spec[:host_port]}"
      end
      content = lines.join("\n") + "\n"
      target = Compose.deploy_env_path(ctx)
      cmd = [
        "mkdir -p #{LuxDeploy.sh(File.dirname(target))}",
        "printf %s #{LuxDeploy.sq(content)} > #{LuxDeploy.sh(target)}.next",
        "mv #{LuxDeploy.sh(target)}.next #{LuxDeploy.sh(target)}"
      ].join(' && ')
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :preflight, summary: 'cannot write deploy.env')
    end
  end

  # Resolve `host_port: null` services to a free remote port from port_range.
  # Stored remotely in manifest.json so repeat deploys keep stable ports.
  module Port
    module_function

    def resolve!(ctx)
      existing_manifest = Manifest.read(ctx.ssh, Manifest.remote_path(ctx.path))
      existing_ports = existing_manifest ? existing_manifest[:services].each_with_object({}) { |(k, v), h| h[k.to_s] = v[:host_port] } : {}

      # Drop this app's own listener ports from `taken`: ss -ltn returns
      # every listening socket on the host, including the currently-running
      # version of this same app. Without this, the manifest port always
      # collides with itself and `allocate` walks the range each deploy.
      own_ports = existing_ports.values.compact
      taken = collect_taken_ports(ctx) - own_ports
      ctx.config[:services].each do |name, spec|
        next if spec[:host_port]
        keep = existing_ports[name.to_s]
        if keep && !taken.include?(keep) && in_range?(keep, spec[:port_range])
          spec[:host_port] = keep
        else
          spec[:host_port] = allocate(name, spec[:port_range], taken)
        end
        taken << spec[:host_port]
      end
      Config.validate_port_uniqueness(ctx.config[:services])
    end

    def in_range?(port, range)
      port.between?(range[0], range[1])
    end

    def allocate(name, range, taken)
      (range[0]..range[1]).each do |port|
        return port unless taken.include?(port)
      end
      raise Error.new(
        "no free port in range for service #{name}",
        expected: "a free port in #{range.inspect}",
        current: "all ports taken: #{taken.sort.join(', ')}",
        need: 'widen the port_range or free a port',
        fix: "edit services.#{name}.port_range",
        category: :preflight
      )
    end

    def collect_taken_ports(ctx)
      # Use remote manifests as the registry, plus current listeners on the
      # loopback to catch anything not tracked by the plugin.
      ports = []
      Manifest.read_all(ctx.ssh, ctx.config[:root]).each do |_, m|
        next if m[:app] == ctx.app
        (m[:services] || {}).each_value { |svc| ports << svc[:host_port] if svc[:host_port] }
      end
      listeners = ctx.ssh.ssh("ss -ltn 2>/dev/null | awk 'NR>1 {print $4}' | sed -n 's/.*:\\([0-9]\\+\\)$/\\1/p' || true")
      ports += listeners.stdout.scan(/\d+/).map(&:to_i) if listeners.success?
      ports.uniq
    end
  end

  module Preflight
    module_function

    def deploy!(ctx)
      ctx.step 'preflight'
      user = ssh_who(ctx)
      ctx.remote_user = user
      ctx.config[:user] = user
      check(ctx, 'command -v docker >/dev/null', 'docker missing', :preflight)
      check(ctx, 'docker compose version >/dev/null', 'docker compose v2 missing', :preflight)
      check(ctx, 'systemctl is-active --quiet caddy', 'caddy not running', :preflight)
      check(ctx, 'sudo -n true', 'passwordless sudo not configured', :preflight)
      check(ctx, "id #{LuxDeploy.sh(ctx.service_user)} >/dev/null 2>&1", "service user #{ctx.service_user} missing", :preflight)
      check(ctx, "sudo test -d #{LuxDeploy.sh(ctx.config[:root])} || sudo install -d -o #{LuxDeploy.sh(ctx.service_user)} -m 0755 #{LuxDeploy.sh(ctx.config[:root])}",
            "cannot ensure #{ctx.config[:root]}", :preflight)
      check(ctx, 'sudo test -d /etc/caddy/sites || sudo install -d -m 0755 /etc/caddy/sites', '/etc/caddy/sites missing', :preflight)
      check_caddy_dns_module!(ctx)
      true
    end

    # Wildcard domains and explicit `tls` blocks both require Caddy to ship
    # with the matching DNS provider plugin. Stock Caddy doesn't include any
    # DNS providers - they must be compiled in via xcaddy. Fail clearly here
    # rather than letting the cert issuance silently fall back and fail later.
    def check_caddy_dns_module!(ctx)
      tls = ctx.config[:tls]
      return unless tls
      provider = tls[:dns_provider]
      module_name = "dns.providers.#{provider}"
      result = ctx.ssh.ssh("caddy list-modules 2>/dev/null | grep -qx #{LuxDeploy.sh(module_name)}")
      return if result.success?
      raise CommandError.new(
        "caddy missing DNS provider plugin '#{provider}'",
        result,
        expected: "caddy list-modules contains #{module_name}",
        need: 'wildcard / DNS-01 cert issuance needs the provider plugin built in',
        fix: "ssh #{ctx.config[:server]} 'sudo apt-get install -y xcaddy && sudo xcaddy build --with github.com/caddy-dns/#{provider} --output /usr/bin/caddy && sudo systemctl restart caddy'",
        category: :preflight
      )
    end

    def ssh_who(ctx)
      result = ctx.ssh.ssh('whoami')
      raise CommandError.new('SSH unreachable', result, expected: 'ssh whoami exits 0', need: 'ssh works', fix: "ssh #{ctx.config[:server]} whoami", category: :preflight) unless result.success?
      user = result.stdout.strip
      user = ctx.config[:user] if user.empty? && ctx.dry_run?
      user
    end

    def check(ctx, cmd, summary, category)
      result = ctx.ssh.ssh(cmd)
      return result if result.success?

      raise CommandError.new(
        "#{summary} on #{ctx.config[:server]}",
        result,
        expected: "#{cmd.inspect} exits 0",
        need: 'preflight check passes before deploy can change remote state',
        fix: "ssh #{ctx.config[:server]} #{LuxDeploy.sq(cmd)}",
        category: category
      )
    end

    def doctor(ctx)
      ssh = ctx.ssh
      root = ctx.config[:root]
      host_checks = [
        ['ssh', 'whoami'],
        ['docker',              'command -v docker >/dev/null'],
        ['docker compose v2',   'docker compose version >/dev/null'],
        ['caddy active',        'systemctl is-active --quiet caddy'],
        ['passwordless sudo',   'sudo -n true'],
        ["service user #{ctx.service_user}", "id #{LuxDeploy.sh(ctx.service_user)} >/dev/null 2>&1"],
        ["#{root} present",     "sudo test -d #{LuxDeploy.sh(root)}"],
        ['/etc/caddy/sites',    'sudo test -d /etc/caddy/sites'],
        ['caddy import wired',  "grep -qF 'import /etc/caddy/sites/*.caddy' /etc/caddy/Caddyfile"]
      ]
      if ctx.config[:tls]
        provider = ctx.config[:tls][:dns_provider]
        host_checks << ["caddy dns:#{provider}", "caddy list-modules 2>/dev/null | grep -qx dns.providers.#{LuxDeploy.sh(provider)}"]
      end
      puts "Server: #{ctx.config[:server]}"
      host_failures = run_checks(ssh, host_checks)
      puts

      app_filter = ctx.options[:app].to_s
      manifests = Manifest.read_all(ssh, root)
      manifests = manifests.select { |_, m| m[:app].to_s == app_filter } unless app_filter.empty?

      if manifests.empty?
        if app_filter.empty?
          puts "No apps with manifest under #{root}/"
        else
          puts "No manifest for app #{app_filter} under #{root}/"
        end
        puts
      end

      app_failures = manifests.sum { |_, m| verify_manifest(ssh, m) }

      total = host_failures + app_failures
      return true if total.zero?

      warn "#{total} check failed#{total == 1 ? '' : 's'}."
      exit EXIT_CODES[:preflight]
    end

    def run_checks(ssh, checks)
      failures = 0
      checks.each do |label, cmd|
        result = ssh.ssh(cmd)
        if result.success?
          puts "  %-32s ok" % label
        else
          puts "  %-32s FAIL" % label
          failures += 1
        end
      end
      failures
    end

    def verify_manifest(ssh, m)
      app = m[:app]
      path = m[:path]
      compose_files = Array(m[:compose_files]).map { |f| "-f #{LuxDeploy.sh(f)}" }.join(' ')
      project = LuxDeploy.sh(m[:compose_project])
      # Slotted deploys (compose_project ends with `-<port>`) use a per-slot
      # deploy.<port>.env file. Legacy deploys keep the single deploy.env.
      slot_suffix = m[:compose_project].to_s[/-(\d+)\z/, 1]
      env_basename = slot_suffix ? "deploy.#{slot_suffix}.env" : 'deploy.env'
      env_file = LuxDeploy.sh("#{path}/config/docker/#{env_basename}")
      checks = []
      checks << ['app dir present', "sudo test -d #{LuxDeploy.sh(path)}"]
      checks << ['manifest present', "sudo test -f #{LuxDeploy.sh(Manifest.remote_path(path))}"]
      checks << ['env file present', "sudo test -f #{LuxDeploy.sh(path)}/shared/.env"]
      checks << ['env file 0600', "[ \"$(sudo stat -c %a #{LuxDeploy.sh(path)}/shared/.env 2>/dev/null)\" = 600 ]"]
      checks << ['caddyfile present', "sudo test -f #{LuxDeploy.sh(m[:caddyfile])}"]
      checks << ['caddy symlink', "test -L #{LuxDeploy.sh(m[:caddy_site])}"]
      checks << ['compose config valid', "docker compose --project-name #{project} --env-file #{env_file} #{compose_files} config -q"]
      (m[:services] || {}).each do |name, spec|
        next unless spec[:host_port]
        checks << ["service #{name} responds on :#{spec[:host_port]}", "curl -fsS -o /dev/null -w '%{http_code}' -m 2 http://127.0.0.1:#{spec[:host_port]}/ >/dev/null"]
      end
      puts "App: #{app}  (path #{path})"
      failures = run_checks(ssh, checks)
      puts
      failures
    end
  end

  module Commands
    module_function

    def deploy(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      Preflight.deploy!(ctx)
      ensure_remote_layout!(ctx)
      # Remember the previous deploy's compose project before slot resolution
      # rewrites it. Used after the swap to clean up the legacy single-project
      # `lux-<app>` containers from any pre-slot deploy.
      prev_manifest = Manifest.read(ctx.ssh, Manifest.remote_path(ctx.path))
      prev_compose_project = prev_manifest && prev_manifest[:compose_project]
      # Pick target slot ports (sibling of currently-live), then re-target
      # ctx so every subsequent compose call hits the new slot's project +
      # env file. Previous slot is left running until the swap succeeds.
      prev_slot_ports = Slot.resolve!(ctx)
      new_slot_port = Slot.apply_to_ctx!(ctx)
      Manifest.verify_no_collisions!(ctx)
      sync_docker_config!(ctx)
      EnvFile.write!(ctx)
      Port.resolve!(ctx)
      DeployEnv.write!(ctx)
      transport = (opts[:transport] || 'archive').to_s
      ctx.step "transport=#{transport}"
      case transport
      when 'archive' then ship_archive!(ctx, build_if_missing: opts[:build])
      when 'registry' then Compose.pull!(ctx)
      else
        raise Error.new(
          'invalid transport',
          expected: "transport in {archive, registry}",
          current: transport,
          need: 'pick a supported transport',
          fix: 'lux deploy --transport archive',
          category: :preflight
        )
      end
      Compose.config!(ctx)
      Compose.verify_services!(ctx)
      ctx.step new_slot_port ? "compose up (slot #{new_slot_port})" : 'compose up'
      Compose.up!(ctx)
      ctx.step 'healthcheck'
      begin
        healthcheck_all!(ctx)
      rescue LuxDeploy::Error
        # New slot failed to come up healthy: tear it down so the previous
        # live slot keeps serving traffic untouched, then re-raise.
        ctx.step 'rollback: stop unhealthy slot'
        Compose.down_quietly!(ctx) if new_slot_port
        raise
      end
      ctx.step new_slot_port ? "caddy swap -> :#{new_slot_port}" : 'caddy install'
      Caddy.install!(ctx)
      if new_slot_port && prev_slot_ports.values.compact.any?
        prev_slot_ports.values.compact.uniq.each do |port|
          next if port == new_slot_port
          ctx.step "stop previous slot (:#{port})"
          Slot.stop_slot!(ctx, port)
        end
      end
      # First slotted deploy after a legacy single-project deploy: tear down
      # the old `lux-<app>` containers by docker label so we don't depend on
      # the now-deleted legacy `deploy.env`. Tolerant - missing project is
      # a no-op. Runs after the caddy swap so a failed healthcheck leaves
      # the legacy containers serving traffic untouched.
      if new_slot_port && prev_compose_project && prev_compose_project !~ /-\d+\z/
        ctx.step "stop legacy project #{prev_compose_project}"
        legacy = LuxDeploy.sh(prev_compose_project)
        ctx.ssh.ssh("docker ps -aq --filter label=com.docker.compose.project=#{legacy} | xargs -r docker rm -f >/dev/null 2>&1; true")
      end
      Manifest.write!(ctx)
      duration = LuxDeploy.duration_since(ctx.started_at)
      ports = ctx.config[:services].map { |n, s| "#{n}=#{s[:host_port]}" }.join(' ')
      puts "deploy ok #{ctx.app} #{ports} duration=#{duration}s"
    end

    def staging(profile, opts = {})
      config = Config.resolve(profile, opts)
      if !opts[:allow_no_db] && !Compose.has_db_service?(config)
        raise Error.new(
          'staging deploy requires a project-local db service',
          expected: 'a `db:` service in one of the compose files',
          current: 'no db service detected',
          need: 'add config/docker/compose.staging.yml or pass --allow-no-db',
          fix: "edit #{config[:compose].first}",
          category: :preflight
        )
      end
      ctx = Context.new(config, opts.merge(staging: true))
      # Refuse to deploy as staging on top of a non-staging manifest. The
      # filesystem is the registry: if /srv/lux-apps/<app>/manifest.json has
      # staging:false, treat that as the production namespace.
      existing = Manifest.read(ctx.ssh, Manifest.remote_path(ctx.path))
      if existing && existing[:staging] == false
        raise Error.new(
          'staging refuses to overwrite a production app',
          expected: "no production manifest at #{ctx.path}/manifest.json",
          current: "app=#{existing[:app]} staging=false already deployed at #{ctx.path}",
          need: 'pick a different --app for the staging stack',
          fix: 'lux deploy:staging pr --app pr-123',
          category: :preflight
        )
      end
      deploy(profile, opts.merge(staging: true))
    end

    def build(profile, opts = {})
      config = Config.resolve(profile, opts)
      Image.build!(config)
      puts "build ok #{config[:app]} archive=#{Image.archive_path(config)}"
    end

    def test(profile, opts = {})
      config = Config.resolve(profile, opts)
      Image.build!(config) if opts[:build]
      Image.local_load!(config) unless Image.local_images_present?(config)
      env_file = local_test_env_file(config)
      argv = Compose.local_argv(config, env_file: env_file)
      head = argv.map { |s| LuxDeploy.sh(s) }.join(' ')
      LuxDeploy.run_local!("#{head} config -q", quiet: opts[:quiet])
      LuxDeploy.run_local!("#{head} up -d --no-build --remove-orphans", quiet: opts[:quiet])
      begin
        run_local_healthchecks!(config)
        puts "test ok #{config[:app]}"
      ensure
        unless opts[:keep]
          LuxDeploy.run_local("#{head} down --remove-orphans", quiet: opts[:quiet])
        end
      end
    end

    def doctor(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      Preflight.doctor(ctx)
    end

    def remove(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      # Prefer the on-host manifest as the source of truth: removing must
      # work even when the local config has drifted. Fall back to the
      # resolved config when no manifest exists.
      manifest = Manifest.read(ctx.ssh, Manifest.remote_path(ctx.path))
      if manifest
        ctx.config[:compose_project] = manifest[:compose_project] if manifest[:compose_project]
        ctx.config[:compose] = Array(manifest[:compose_files]).map do |abs|
          abs.start_with?(ctx.path) ? abs.sub("#{ctx.path}/", '') : abs
        end if manifest[:compose_files]
      end
      # Slot-aware teardown: tear down every `lux-<app>-<port>` project so a
      # half-finished swap (both slots running) is cleaned up. Fall back to
      # the single-project Compose.down! for deploys made before slots
      # existed (manifest still has the legacy `lux-<app>` project name).
      slot_projects = Slot.known_projects(ctx)
      if slot_projects.empty?
        Compose.down!(ctx, volumes: opts[:volumes])
      else
        slot_projects.each do |project|
          port = project.split('-').last.to_i
          ctx.step "remove slot #{project}"
          Slot.stop_slot!(ctx, port)
        end
      end
      Caddy.remove!(ctx)
      if opts[:purge]
        ctx.ssh.ssh!("sudo rm -rf #{LuxDeploy.sh(ctx.path)}", category: :source, summary: 'cannot purge app dir')
      end
      puts "remove ok #{ctx.app} path=#{ctx.path}#{opts[:purge] ? ' purged' : ''}"
    end

    def ssh(profile, opts = {})
      config = Config.resolve(profile, opts)
      ssh = SSH.new(config, dry_run: opts[:dry_run], quiet: opts[:quiet])
      status = ssh.shell(remote_cwd: config[:path])
      exit status unless status.zero?
    end

    def logs(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      apply_live_slot_from_manifest!(ctx)
      head = Compose.shell(
        project: ctx.config[:compose_project],
        env_file: Compose.deploy_env_path(ctx),
        compose_files: Compose.remote_compose_files(ctx),
        cmd: ['logs', opts[:follow] ? '-f' : nil, opts[:tail] ? "--tail=#{opts[:tail]}" : nil, opts[:service]].compact
      )
      argv = ['ssh', opts[:follow] ? '-t' : nil, ctx.config[:server], head].compact
      puts "+ #{argv.join(' ')}" unless ctx.quiet?
      system(*argv)
      exit $?.exitstatus.to_i unless $?.success?
    end

    def llm_prepare(_profile, opts = {})
      LLMPrepare.run(opts)
    end

    def compose(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      passthrough = Array(opts[:args])
      if passthrough.empty?
        raise Error.new(
          'no docker compose subcommand passed',
          expected: 'lux deploy:compose [PROFILE] -- <docker compose args>',
          current: 'no args after --',
          need: 'pass a docker compose subcommand',
          fix: 'lux deploy:compose -- ps',
          category: :preflight
        )
      end
      apply_live_slot_from_manifest!(ctx)
      head = Compose.shell(
        project: ctx.config[:compose_project],
        env_file: Compose.deploy_env_path(ctx),
        compose_files: Compose.remote_compose_files(ctx),
        cmd: passthrough
      )
      argv = ['ssh', '-t', ctx.config[:server], head]
      puts "+ #{argv.join(' ')}" unless ctx.quiet?
      system(*argv)
      exit $?.exitstatus.to_i unless $?.success?
    end

    # Read the on-host manifest and steer ctx at the live slot so logs /
    # compose / inspection commands target the running stack instead of a
    # stale default project name. No-op when no manifest exists yet. Only
    # overrides the deploy env path when the manifest's compose_project
    # follows the slotted `lux-<app>-<port>` form - legacy deploys keep the
    # default `config/docker/deploy.env`.
    def apply_live_slot_from_manifest!(ctx)
      manifest = Manifest.read(ctx.ssh, Manifest.remote_path(ctx.path))
      return unless manifest
      project = manifest[:compose_project]
      ctx.config[:compose_project] = project if project
      if project && project =~ /-(\d+)\z/
        ctx.config[:deploy_env_path] = Slot.deploy_env_file_for(ctx, Regexp.last_match(1).to_i)
      end
    end

    def ensure_remote_layout!(ctx)
      su = LuxDeploy.sh(ctx.service_user)
      root = LuxDeploy.sh(ctx.config[:root])
      home = LuxDeploy.sh(File.dirname(ctx.config[:root]))
      path = LuxDeploy.sh(ctx.path)
      cmd = [
        # service_user's home must be traversable so caddy can follow the
        # /etc/caddy/sites/*.caddy symlink into /home/<user>/lux-apps/<app>.
        # 0711 lets caddy `cd` through without exposing dotfiles inside.
        "sudo chmod 0711 #{home}",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{root}",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{path}",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{path}/config",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{path}/config/docker",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{path}/shared",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{path}/shared/log",
        "sudo install -d -o #{su} -g #{su} -m 0755 #{path}/shared/tmp"
      ].join(' && ')
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'cannot ensure remote app layout')
    end

    def sync_docker_config!(ctx)
      local = File.join(ctx.config[:app_root], 'config/docker')
      unless File.directory?(local)
        raise Error.new(
          'local config/docker missing',
          expected: "#{local} exists",
          current: 'no docker config dir',
          need: 'create config/docker with compose.yml',
          fix: "mkdir -p #{local} && edit #{local}/compose.yml",
          category: :preflight
        )
      end
      ctx.ssh.rsync_to!(local, "#{ctx.path}/config/docker")
    end

    def ship_archive!(ctx, build_if_missing: false)
      local = Image.archive_path(ctx.config)
      if !File.file?(local)
        if build_if_missing
          Image.build!(ctx.config)
        else
          raise Error.new(
            'image archive missing',
            expected: "#{local} exists",
            current: 'no archive built',
            need: 'run lux deploy:build first, or pass --build',
            fix: "lux deploy:build #{ctx.config[:profile]}",
            category: :preflight
          )
        end
      end
      ctx.step 'upload image archive'
      Image.upload!(ctx)
      ctx.step 'docker load'
      Image.remote_load!(ctx)
    end

    def healthcheck_all!(ctx)
      defaults = ctx.config[:healthcheck_defaults] || {}
      ctx.config[:services].each do |name, spec|
        hc = spec[:healthcheck] || {}
        path = hc[:path] || defaults[:path] || '/'
        timeout = hc[:timeout] || defaults[:timeout] || 30
        statuses = (hc[:expect_status] || defaults[:expect_status] || [200, 301, 302]).join('|')
        port = spec[:host_port]
        next unless port
        url = "http://127.0.0.1:#{port}#{path}"
        cmd = <<~SH
          end=$((SECONDS+#{timeout}))
          last=''
          while [ $SECONDS -lt $end ]; do
            code=$(curl -fsS -o /dev/null -w '%{http_code}' #{LuxDeploy.sq(url)} 2>/tmp/lux-health.err || true)
            last=$code
            echo "$code" | grep -Eq '^(#{statuses})$' && exit 0
            sleep 1
          done
          err=$(cat /tmp/lux-health.err 2>/dev/null || true)
          echo "status=$last stderr=$err" >&2
          exit 1
        SH
        result = ctx.ssh.ssh(cmd)
        next if result.success?

        raise CommandError.new(
          "health check failed for service #{name}",
          result,
          expected: "GET #{url} returns one of #{statuses} within #{timeout}s",
          need: 'service boots cleanly and serves the configured health path',
          fix: "ssh #{ctx.config[:server]} 'docker compose --project-name #{ctx.config[:compose_project]} logs --tail=200 #{spec[:compose_service]}'",
          category: :healthcheck
        )
      end
    end

    def run_local_healthchecks!(config)
      config[:services].each do |name, spec|
        port = spec[:host_port]
        next unless port
        hc = spec[:healthcheck] || {}
        path = hc[:path] || '/'
        timeout = hc[:timeout] || 30
        statuses = (hc[:expect_status] || [200, 301, 302]).join('|')
        url = "http://127.0.0.1:#{port}#{path}"
        cmd = "end=$((SECONDS+#{timeout})); last=''; while [ $SECONDS -lt $end ]; do code=$(curl -fsS -o /dev/null -w '%{http_code}' #{LuxDeploy.sq(url)} 2>/dev/null || true); last=$code; echo $code | grep -Eq '^(#{statuses})$' && exit 0; sleep 1; done; echo \"#{name} status=$last\" >&2; exit 1"
        LuxDeploy.run_local!("bash -c #{LuxDeploy.sq(cmd)}", quiet: config[:quiet])
      end
    end

    def local_test_env_file(config)
      dir = Image.archive_dir(config)
      FileUtils.mkdir_p(File.join(dir, 'log'))
      FileUtils.mkdir_p(File.join(dir, 'tmp'))
      lines = []
      lines << "LUX_RUNTIME_ENV_FILE=#{File.join(dir, 'runtime.env')}"
      lines << "LUX_LOG_DIR=#{File.join(dir, 'log')}"
      lines << "LUX_TMP_DIR=#{File.join(dir, 'tmp')}"
      lines << "LUX_SOURCE_DIR=#{config[:app_root]}"
      lines << "COMPOSE_PROJECT_NAME=#{config[:compose_project]}-test"
      config[:images].each { |svc, ref| lines << "#{svc.to_s.upcase}_IMAGE=#{ref}" }
      config[:services].each do |name, spec|
        port = spec[:host_port] || (spec[:port_range] && spec[:port_range][0])
        lines << "#{name.to_s.upcase}_PORT=#{port}" if port
      end
      env_file = File.join(dir, 'test.env')
      File.write(env_file, lines.join("\n") + "\n")
      # runtime.env mirrors the deployable env block - used by the running
      # containers. Resolve required/$generate values, then expand any
      # `{{env.KEY}}` references so DB_URL-style composed values work the
      # same locally as they do on the remote host.
      resolved = config[:env].each_with_object({}) do |(k, v), out|
        case v
        when true then out[k.to_s] = ENV[k.to_s] || 'test'
        when false, nil
          out[k.to_s] = ENV[k.to_s] if ENV[k.to_s]
        when Config::SECRET_GEN_TOKEN then out[k.to_s] = SecureRandom.hex(16)
        else out[k.to_s] = v.to_s
        end
      end
      lookup = ->(key) { resolved[key].to_s }
      expanded = resolved.each_with_object({}) do |(k, v), h|
        h[k] = v.is_a?(String) ? Config.interpolate_env_refs(v, lookup) : v
      end
      File.write(File.join(dir, 'runtime.env'), expanded.map { |k, v| "#{k}=#{v}" }.join("\n") + "\n")
      env_file
    end
  end
end
