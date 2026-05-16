require 'erb'
require 'fileutils'
require 'json'
require 'open3'
require 'pathname'
require 'tmpdir'
require 'shellwords'
require 'time'

module LuxDeploy
  ROOT ||= Pathname.new(File.expand_path('..', __dir__))

  EXIT_CODES ||= {
    preflight: 10,
    source: 20,
    db: 30,
    systemd: 40,
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
    attr_accessor :remote_user, :bundle, :release

    def initialize(config, options)
      @config = config
      @options = options
      @started_at = Time.now.utc
      @ssh = SSH.new(config, dry_run: options[:dry_run], quiet: options[:quiet])
      @remote_user = config[:user]
      @bundle = nil
      @release = nil
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

    def ruby
      config[:ruby]
    end

    def port
      config[:port]
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
    require_relative 'lux_deploy_log'
    require_relative 'lux_deploy_port'
    require_relative 'lux_deploy_release'
    require_relative 'lux_deploy_postgres'
    require_relative 'lux_deploy_systemd'
    require_relative 'lux_deploy_caddy'
    require_relative 'lux_deploy_prepare'
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

  # Alias retained for call sites that distinguish "shell arg" (sh) from
  # "single-quoted SQL/shell payload" (sq). Both go through Shellwords.escape.
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

  def hash_port(app)
    3000 + (app.bytes.sum % 1000)
  end

  # Wrap a remote shell command so it runs as the service user. When the SSH
  # user is already the service user, returns the command unchanged.
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
  module EnvFile
    module_function

    def write!(ctx)
      lines = resolved_lines(ctx.config[:env])
      return if lines.empty?

      keys = lines.map { |line| line.split('=', 2).first }
      pattern = "^(#{keys.join('|')})="
      content = lines.join("\n") + "\n"
      cmd = [
        "touch #{LuxDeploy.sh(ctx.path)}/shared/.env",
        "grep -vE #{LuxDeploy.sq(pattern)} #{LuxDeploy.sh(ctx.path)}/shared/.env > #{LuxDeploy.sh(ctx.path)}/shared/.env.next || true",
        "printf %s #{LuxDeploy.sq(content)} >> #{LuxDeploy.sh(ctx.path)}/shared/.env.next",
        "mv #{LuxDeploy.sh(ctx.path)}/shared/.env.next #{LuxDeploy.sh(ctx.path)}/shared/.env",
        "chmod 0600 #{LuxDeploy.sh(ctx.path)}/shared/.env"
      ].join(' && ')
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :preflight, summary: 'cannot write remote .env')
    end

    def resolved_lines(env)
      env.each_with_object([]) do |(key, value), lines|
        case value
        when true
          local = ENV[key.to_s]
          if local.nil? || local.empty?
            raise Error.new(
              'required env var not set locally',
              expected: "#{key} present in caller's environment",
              current: "#{key} unset",
              need: "export #{key} before running deploy (declared as true in deploy.json env block)",
              fix: "export #{key}=VALUE",
              category: :preflight
            )
          end
          lines << env_line(key, local)
        when false
          local = ENV[key.to_s]
          lines << env_line(key, local) if local
        else
          lines << env_line(key, value.to_s)
        end
      end
    end

    def env_line(key, value)
      "#{key}=#{Shellwords.escape(value.to_s)}"
    end
  end

  module Preflight
    module_function

    def deploy!(ctx)
      ctx.step 'preflight'
      user = check(ctx, 'whoami', 'SSH unreachable', :preflight).stdout.strip
      user = ctx.config[:user] if user.empty? && ctx.dry_run?
      ctx.remote_user = user
      ctx.config[:user] = user
      ctx.bundle = "/home/#{ctx.service_user}/.local/share/mise/installs/ruby/#{ctx.ruby}/bin/bundle"
      check(ctx, 'sudo -n true', 'passwordless sudo not configured', :preflight)
      check(ctx, "id #{LuxDeploy.sh(ctx.service_user)} >/dev/null 2>&1", "service user #{ctx.service_user} missing", :preflight)
      check(ctx, "sudo test -x #{LuxDeploy.sh(ctx.bundle)}", 'bundler missing on host', :preflight)
      check(ctx, 'systemctl is-active --quiet caddy', 'caddy not running', :preflight)
      check(ctx, 'systemctl is-active --quiet postgresql || systemctl is-active --quiet postgres', 'postgres not running', :preflight)
      check(ctx, "sudo -u postgres psql -c 'select 1' >/dev/null", 'sudo postgres psql failed', :preflight)
      path_check = "if sudo test -e #{LuxDeploy.sh(ctx.path)}; then sudo test -d #{LuxDeploy.sh(ctx.path)}; fi"
      check(ctx, path_check, 'target path not a directory', :preflight)
      EnvFile.resolved_lines(ctx.config[:env])
      true
    end

    def doctor(ctx)
      su = ctx.service_user
      bundle = "/home/#{su}/.local/share/mise/installs/ruby/#{ctx.ruby}/bin/bundle"
      caddy_owner_check = "stat -c '%U' /etc/caddy/sites 2>/dev/null | grep -qx #{LuxDeploy.sh(su)}"
      log_owner_check = "stat -c '%U' /var/log/lux-deploy 2>/dev/null | grep -qx #{LuxDeploy.sh(su)}"
      checks = [
        ['ssh', 'whoami', 'SSH unreachable'],
        ['passwordless sudo', 'sudo -n true', 'passwordless sudo not configured'],
        ["service user #{su}", "id #{LuxDeploy.sh(su)} >/dev/null 2>&1", "service user #{su} missing"],
        ["#{su} ruby/bundler", "sudo test -x #{LuxDeploy.sh(bundle)}", 'bundler missing on host'],
        ['caddy active', 'systemctl is-active --quiet caddy', 'caddy not running'],
        ['postgres active', 'systemctl is-active --quiet postgresql || systemctl is-active --quiet postgres', 'postgres not running'],
        ['sudo -u postgres psql', "sudo -u postgres psql -c 'select 1' >/dev/null", 'sudo postgres psql failed'],
        ["/etc/caddy/sites owned by #{su}", caddy_owner_check, 'caddy sites dir not owned by service user'],
        ["/var/log/lux-deploy owned by #{su}", log_owner_check, 'deploy log dir not owned by service user']
      ]
      puts "Host: #{ctx.config[:host]}"
      puts
      failures = []
      checks.each do |label, cmd, summary|
        result = ctx.ssh.ssh(cmd)
        if result.success?
          puts "  %-30s ok" % label
        else
          puts "  %-30s FAIL" % label
          failures << build_error(ctx, summary, result, cmd)
        end
      end
      puts
      failures.each { |failure| warn failure.to_s }
      return true if failures.empty?

      warn "#{failures.size} check failed#{'s' unless failures.size == 1}."
      exit EXIT_CODES[:preflight]
    end

    def check(ctx, cmd, summary, category)
      result = ctx.ssh.ssh(cmd)
      return result if result.success?

      raise build_error(ctx, summary, result, cmd, category: category)
    end

    def build_error(ctx, summary, result, cmd, category: :preflight)
      fix = case summary
      when /sudo/
        "ssh #{ctx.config[:host]} 'echo \"#{ctx.service_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/lux-deploy && sudo chmod 0440 /etc/sudoers.d/lux-deploy'"
      when /service user/
        "lux deploy:prepare --host #{ctx.config[:host]} --service-user #{ctx.service_user}"
      when /caddy/
        "lux deploy:prepare --with caddy --host #{ctx.config[:host]}"
      when /postgres/
        "lux deploy:prepare --with postgres --host #{ctx.config[:host]}"
      when /bundler|ruby/
        "lux deploy:prepare --host #{ctx.config[:host]} --ruby #{ctx.ruby}"
      else
        "ssh #{ctx.config[:host]} #{LuxDeploy.sq(cmd)}"
      end
      CommandError.new(
        "#{summary} on #{ctx.config[:host]}",
        result,
        expected: "#{cmd.inspect} exits 0",
        need: 'preflight check passes before deploy can change remote state',
        fix: fix,
        category: category
      )
    end
  end

  module Commands
    module_function

    def deploy(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      begin
        Preflight.deploy!(ctx)
        Port.resolve(ctx)
        Release.ensure_layout(ctx)
        Release.create(ctx)
        Log.append(ctx, "deploy start release=#{ctx.release} ref=#{source_ref(ctx)}")
        ctx.step 'source sync'
        Release.sync_source(ctx)
        EnvFile.write!(ctx)
        Release.symlink_shared(ctx)
        ctx.step 'bundle install'
        Release.bundle_install(ctx)
        ctx.step 'db ensure'
        Postgres.ensure!(ctx)
        ctx.step 'migrate'
        Release.migrate(ctx)
        ctx.step 'systemd install'
        Systemd.install!(ctx)
        ctx.step 'atomic swap'
        Release.swap_current(ctx)
        Systemd.restart!(ctx)
        ctx.step 'healthcheck'
        healthcheck!(ctx)
        ctx.step 'caddy'
        Caddy.install!(ctx)
        Release.prune(ctx)
        duration = LuxDeploy.duration_since(ctx.started_at)
        Log.append(ctx, "deploy ok duration=#{duration}s")
        puts "deploy ok #{ctx.app} release=#{ctx.release} port=#{ctx.port} db=#{ctx.config.dig(:db, :name)} domain=#{ctx.config[:domain]} duration=#{duration}s"
      rescue Error => e
        Log.append_best_effort(ctx, "deploy fail step=#{e.category} exit=#{e.code}")
        raise
      end
    end

    def prepare(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      Prepare.run(ctx, with: parse_with(opts[:with]))
    end

    def doctor(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      Preflight.doctor(ctx)
    end

    def rollback(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      Preflight.deploy!(ctx)
      Log.append(ctx, 'rollback start')
      Release.rollback(ctx)
      Systemd.restart!(ctx)
      Log.append(ctx, "rollback ok release=#{ctx.release}")
      puts "rollback ok #{ctx.app} release=#{ctx.release}"
    end

    def remove(profile, opts = {})
      config = Config.resolve(profile, opts)
      ctx = Context.new(config, opts)
      Log.append_best_effort(ctx, 'remove start')
      Systemd.uninstall!(ctx)
      Caddy.remove!(ctx)
      ctx.ssh.ssh!("rm -rf #{LuxDeploy.sh(ctx.path)}", category: :source, summary: 'cannot remove deploy directory')
      Postgres.drop!(ctx) if opts[:with_db]
      Log.append_best_effort(ctx, 'remove ok')
      puts "remove ok #{ctx.app} path=#{ctx.path}"
    end

    def deploy_log(profile, opts = {})
      config = Config.resolve(profile, opts)
      Log.tail(config, app: opts[:app], lines: opts[:tail] || 50, follow: opts[:follow], dry_run: opts[:dry_run], quiet: opts[:quiet])
    end

    def tail(profile, opts = {})
      config = Config.resolve(profile, opts)
      Systemd.tail(config, lines: opts[:lines] || 100, follow: opts[:follow], dry_run: opts[:dry_run], quiet: opts[:quiet])
    end

    def list(profile, opts = {})
      config = Config.resolve(profile, opts)
      ssh = SSH.new(config, dry_run: opts[:dry_run], quiet: opts[:quiet])
      cmd = <<~SH
        { for f in /etc/caddy/sites/*.caddy; do [ -f "$f" ] || continue; app=$(basename "$f" .caddy); domain=$(head -n 1 "$f" | sed 's/ {//'); port=$(grep -Eo 'localhost:[0-9]+' "$f" | head -n1 | cut -d: -f2); echo "$app|$domain|$port|caddy"; done; } 2>/dev/null
        systemctl list-units 'lux-web-*.service' 'lux-job-*.service' --no-legend --no-pager 2>/dev/null | awk '{print $1"|"$4}'
        find /var/www -maxdepth 3 -name current -type l -printf '%h|%l\n' 2>/dev/null
      SH
      result = ssh.ssh(cmd)
      output = filter_list(result.stdout, opts[:app])
      puts output
      warn result.stderr unless result.stderr.empty?
      exit result.status unless result.success?
    end

    def filter_list(stdout, app)
      return stdout unless app && !app.empty?
      stdout.each_line.select { |line| line.include?(app) }.join
    end

    def healthcheck!(ctx)
      hc = ctx.config[:healthcheck]
      statuses = hc[:expect_status].join('|')
      url = "http://localhost:#{ctx.port}#{hc[:path]}"
      cmd = <<~SH
        end=$((SECONDS+#{hc[:timeout]}))
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
      return if result.success?

      raise CommandError.new(
        "deploy health check failed on lux-web-#{ctx.app}",
        result,
        expected: "GET #{url} returns an expected status within #{hc[:timeout]}s",
        need: 'app boots cleanly on the new release',
        fix: "ssh #{ctx.config[:host]} sudo journalctl -u lux-web-#{ctx.app} -n 100 --no-pager",
        category: :healthcheck
      )
    end

    def source_ref(ctx)
      if ctx.config[:branch]
        "git:#{ctx.config[:branch]}"
      else
        "rsync:#{ctx.config[:src]}"
      end
    end

    def parse_with(value)
      Array(value).flat_map { |item| item.to_s.split(',') }.reject(&:empty?)
    end
  end
end
