require 'fileutils'
require 'pathname'
require 'open3'
require 'set'
require 'shellwords'
require 'yaml'

module LuxDeploy
  ROOT ||= Pathname.new(File.expand_path('..', __dir__))

  # Baked-in conventions. If you need to change these, the plugin is the
  # wrong tool - go run docker:deploy instead.
  SERVICE_USER   ||= 'deployer'
  REMOTE_BASE    ||= '/home/deployer/lux-apps'
  PORT_RANGE     ||= (3010..3990).step(10).to_a
  CADDY_SITES    ||= '/etc/caddy/sites'
  SYSTEMD_DIR    ||= '/etc/systemd/system'
  MAIN_BRANCHES  ||= %w[master main]

  class Error < StandardError
    def to_s
      "ERROR: #{super}"
    end
  end
end

require_relative 'lux_deploy_ssh'
require_relative 'lux_deploy_template'
require_relative 'lux_deploy_doctor'

module LuxDeploy
  module Commands
    module_function

    # -------- deploy:up -----------------------------------------------------

    def up(opts)
      ctx = Context.build(opts)
      step "deploy #{ctx.app} (branch #{ctx.branch}) -> #{ctx.host}"

      ensure_remote_dirs(ctx)
      ctx.port ||= allocate_port(ctx)
      render_artifacts(ctx)

      step 'cache gems into vendor/cache'
      # Ship .gem files with the rsync so the server skips downloads for
      # platform-matching gems. Native gems (pg etc.) cached for darwin will
      # be re-fetched from rubygems on Debian and built locally - bundler
      # handles that fallback automatically, so a failure here is non-fatal.
      system('bundle', 'cache', '--no-install') or warn 'bundle cache failed, continuing without local cache'

      step 'rsync code'
      ctx.ssh.rsync('./', "#{ctx.app_dir}/new-release/",
                    excludes: %w[.git tmp log node_modules .DS_Store coverage])

      step 'symlink shared dirs into new-release'
      ctx.ssh.run(<<~SH, as: :deployer)
        cd #{Shellwords.escape(ctx.app_dir)}/new-release && \
        ln -sfn ../shared/tmp tmp && \
        ln -sfn ../shared/log log && \
        ln -sfn ../.env       .env
      SH

      step 'write rendered .env / systemd.service / caddy.config'
      upload_artifacts(ctx)

      step 'bundle install'
      # Bundler 4 dropped --deployment / --without flags. We also avoid
      # `deployment=true` because it implies `frozen=true`, which breaks apps
      # whose Gemfile resolves to different sources per environment (e.g.
      # local path -> .gems fallback). A fresh release dir has no prior
      # bundle config, so regenerating the lockfile is local to this release.
      ctx.ssh.stream(
        "cd #{Shellwords.escape(ctx.app_dir)}/new-release && " \
        '( [ -f mise.toml ] && mise trust mise.toml >/dev/null 2>&1 || true ) && ' \
        'bundle config set --local frozen false && ' \
        "bundle config set --local path vendor/bundle && " \
        "bundle config set --local without 'development test' && " \
        'bundle install --jobs 4 --retry 2',
        as: :deployer
      )

      step 'smoke test (lux e 1)'
      ok = ctx.ssh.stream(
        "cd #{Shellwords.escape(ctx.app_dir)}/new-release && bundle exec lux e 1",
        as: :deployer, allow_fail: true
      )
      unless ok
        warn 'smoke failed; rolling back (release/ untouched, removing new-release/)'
        ctx.ssh.run("rm -rf #{Shellwords.escape(ctx.app_dir)}/new-release", as: :deployer, allow_fail: true)
        raise Error.new("smoke test failed (#{ctx.app})")
      end

      step 'atomic release swap'
      ctx.ssh.run(<<~SH, as: :deployer)
        cd #{Shellwords.escape(ctx.app_dir)} && \
        rm -rf old-release && \
        ( [ -d release ] && mv release old-release || true ) && \
        mv new-release release
      SH

      step 'install systemd + caddy symlinks'
      install_system_symlinks(ctx)

      step 'reload services'
      ctx.ssh.run(<<~SH)
        systemctl daemon-reload && \
        systemctl enable --now lux-web-#{ctx.app} && \
        systemctl restart lux-web-#{ctx.app} && \
        systemctl reload caddy
      SH

      if ctx.job_template?
        step 'restart job service'
        ctx.ssh.run(<<~SH)
          systemctl enable --now lux-job-#{ctx.app} && \
          systemctl restart lux-job-#{ctx.app}
        SH
      end

      step "done. https://#{ctx.domain} (port #{ctx.port})"
    end

    # -------- deploy:destroy ------------------------------------------------

    def destroy(opts)
      ctx = Context.build(opts, render: false)
      step "destroy #{ctx.app} on #{ctx.host}"
      confirm_destroy!(ctx) unless opts[:yes]

      step 'stop + disable systemd units'
      ctx.ssh.run(<<~SH, allow_fail: true)
        systemctl disable --now lux-web-#{ctx.app} 2>/dev/null || true
        systemctl disable --now lux-job-#{ctx.app} 2>/dev/null || true
        rm -f #{SYSTEMD_DIR}/lux-web-#{ctx.app}.service
        rm -f #{SYSTEMD_DIR}/lux-job-#{ctx.app}.service
        systemctl daemon-reload
      SH

      step 'unlink caddy site'
      ctx.ssh.run(<<~SH, allow_fail: true)
        rm -f #{CADDY_SITES}/#{ctx.app}.caddy
        systemctl reload caddy || true
      SH

      step "rm -rf #{ctx.app_dir}"
      ctx.ssh.run("rm -rf #{Shellwords.escape(ctx.app_dir)}", as: :deployer, allow_fail: true)

      step 'done.'
    end

    # -------- deploy:redeploy ----------------------------------------------

    def redeploy(opts)
      destroy(opts)
      up(opts)
    end

    # -------- deploy:doctor ------------------------------------------------

    def doctor(opts)
      host = Context.read_host(opts)
      ssh  = SSH.new(host, dry_run: false)
      Doctor.run(ssh, fix: opts.fetch(:fix, true))
    end

    # -------- deploy:app:init ----------------------------------------------

    # Copy every shipped template into ./config/deploy/. Existing files are
    # left untouched so re-running this is safe. The files are raw - users
    # edit them in place and the deploy step renders {{VAR}} placeholders.
    def init(_opts)
      dest_dir   = './config/deploy'
      shipped_dir = LuxDeploy::ROOT.join('templates').to_s
      FileUtils.mkdir_p(dest_dir)
      step "init #{dest_dir}/ from #{shipped_dir}"

      Dir.children(shipped_dir).sort.each do |name|
        src = File.join(shipped_dir, name)
        dst = File.join(dest_dir, name)
        next unless File.file?(src)

        if File.exist?(dst)
          $stderr.puts "  skip   #{name} (exists)"
        else
          FileUtils.cp(src, dst)
          $stderr.puts "  write  #{name}"
        end
      end

      $stderr.puts "done. edit #{dest_dir}/.env (SECRET, DB_URL, DOMAIN) and #{dest_dir}/server, then run 'lux deploy:doctor' and 'lux deploy:up'"
    end

    # -------- deploy:server:ssh --------------------------------------------

    def server_ssh(opts)
      ctx = Context.build(opts, render: false)
      step "ssh #{ctx.app_dir}/release (deployer)"
      ctx.ssh.exec(
        "cd #{Shellwords.escape(ctx.app_dir)}/release && exec bash -li",
        as: :deployer
      )
    end

    # -------- deploy:server:log --------------------------------------------

    def server_log(opts)
      ctx = Context.build(opts, render: false)
      step "journalctl -fu lux-web-#{ctx.app}"
      ctx.ssh.exec("journalctl -u lux-web-#{ctx.app} -n 200 -f")
    end

    # -------- deploy:server:restart ----------------------------------------

    def server_restart(opts)
      ctx = Context.build(opts, render: false)
      step "restart lux-web-#{ctx.app}"
      ctx.ssh.run("systemctl restart lux-web-#{ctx.app}")
    end

    # -------- deploy:server:status -----------------------------------------

    def server_status(opts)
      ctx = Context.build(opts, render: false)
      step "status lux-web-#{ctx.app}"
      ctx.ssh.stream("systemctl status lux-web-#{ctx.app} --no-pager", allow_fail: true)
    end

    # -------- deploy:db:psql -----------------------------------------------

    # Sources the remote .env so DB_URL never appears in the ssh command
    # line (which the logger would print).
    def db_psql(opts)
      ctx = Context.build(opts, render: false)
      step "psql #{ctx.app}"
      ctx.ssh.exec(<<~SH, as: :deployer)
        set -a && . #{Shellwords.escape(ctx.app_dir)}/.env && set +a && exec psql "$DB_URL"
      SH
    end

    # -------- deploy:db:pull -----------------------------------------------

    # Dumps remote DB (via DB_URL from server .env) and restores into the
    # local DB pointed to by local $DB_URL. Drops + recreates local DB.
    def db_pull(opts)
      ctx = Context.build(opts, render: false)
      step "db:pull #{ctx.app} -> local"

      local_db_url = ENV['DB_URL'].to_s
      raise Error.new('local $DB_URL not set') if local_db_url.empty?
      local_db_name = local_db_url.split('/').last.to_s.split('?').first
      raise Error.new("can't parse db name from local DB_URL") if local_db_name.empty?

      FileUtils.mkdir_p('./tmp')
      remote_dump = "/tmp/lux-#{ctx.app}-dump.sql.gz"
      local_dump  = "./tmp/#{ctx.app}-dump.sql.gz"
      local_sql   = local_dump.sub(/\.gz$/, '')

      step "pg_dump on #{ctx.host} -> #{remote_dump}"
      ctx.ssh.stream(<<~SH, as: :deployer)
        set -a && . #{Shellwords.escape(ctx.app_dir)}/.env && set +a && \
        pg_dump --no-privileges --no-owner "$DB_URL" | gzip > #{Shellwords.escape(remote_dump)}
      SH

      step "scp -> #{local_dump}"
      FileUtils.rm_f(local_dump)
      ctx.ssh.scp_from(remote_dump, local_dump)
      ctx.ssh.run("rm -f #{Shellwords.escape(remote_dump)}", as: :deployer, allow_fail: true)

      step 'gunzip'
      FileUtils.rm_f(local_sql)
      system('gunzip', local_dump) or raise Error.new('gunzip failed')

      step "dropdb -f #{local_db_name} && createdb #{local_db_name}"
      system('dropdb', '-f', local_db_name) # may not exist; ignore
      system('createdb', local_db_name) or raise Error.new("createdb #{local_db_name} failed")

      step 'psql restore'
      system('bash', '-c', "psql #{Shellwords.escape(local_db_url)} < #{Shellwords.escape(local_sql)}") \
        or raise Error.new('psql restore failed')

      step "done. imported into #{local_db_name}"
    end

    # -------- helpers ------------------------------------------------------

    def step(msg)
      $stderr.puts "==> #{msg}"
    end

    def confirm_destroy!(ctx)
      $stderr.print "type '#{ctx.domain}' to confirm destroy: "
      typed = $stdin.gets.to_s.strip
      raise Error.new('aborted; pass --yes to skip prompt') unless typed == ctx.domain
    end

    def ensure_remote_dirs(ctx)
      step 'ensure remote dirs'
      ctx.ssh.run(<<~SH, as: :deployer)
        mkdir -p #{Shellwords.escape(ctx.app_dir)}/shared/tmp
        mkdir -p #{Shellwords.escape(ctx.app_dir)}/shared/log
      SH
    end

    def allocate_port(ctx)
      step 'allocate port'
      # Read PORT from existing .env if present (re-deploys reuse it)
      existing = ctx.ssh.run(
        "[ -f #{Shellwords.escape(ctx.app_dir)}/.env ] && " \
        "grep -E '^PORT=' #{Shellwords.escape(ctx.app_dir)}/.env || true",
        as: :deployer, allow_fail: true
      ).strip
      if existing =~ /^PORT=(\d+)/
        port = $1.to_i
        $stderr.puts "    reusing existing PORT=#{port}"
        return port
      end

      # Scan free port from PORT_RANGE
      in_use = ctx.ssh.run("ss -tlnH | awk '{print $4}' | sed 's/.*://'", allow_fail: true)
        .lines.map { |l| l.strip.to_i }.to_set
      free = PORT_RANGE.find { |p| !in_use.include?(p) }
      raise Error.new("no free port in 3010..3990 (step 10)") unless free
      $stderr.puts "    allocated PORT=#{free}"
      free
    end

    # Two-pass render:
    #   1. compose base vars (git + yaml + plugin-provided), render .env
    #   2. parse .env, merge result into vars (env overrides yaml so staging
    #      branches can redefine DOMAIN), render the remaining templates.
    def render_artifacts(ctx)
      step 'render templates'

      base_vars = ctx.base_vars.merge(
        PORT:     ctx.port,
        DIR:      ctx.app_dir,
        RUBY:     ctx.ruby_path,
        RUBY_DIR: File.dirname(ctx.ruby_path)
      )

      env_rendered = Template.render(ctx.read_template(ctx.env_template_name), base_vars)
      env_hash     = Template.parse_env(env_rendered)

      all_vars = base_vars.merge(env_hash)
      ctx.domain = (env_hash[:DOMAIN] || base_vars[:DOMAIN]).to_s
                    .split(',').first.to_s.strip.sub(/^\*\./, '')
      raise Error.new('DOMAIN resolved to empty') if ctx.domain.empty?

      ctx.rendered = {
        '.env'            => env_rendered,
        'caddy.config'    => Template.render(ctx.read_template('caddy.conf'), all_vars),
        'systemd.service' => Template.render(ctx.read_template('systemd.service'), all_vars)
      }
      if ctx.job_template?
        ctx.rendered['systemd.job.service'] = Template.render(ctx.read_template('job.service'), all_vars)
      end
    end

    # Upload rendered files atomically (write to .new, mv).
    # .env is 0600 (secrets); other artifacts are 0644 so caddy/systemd
    # (running as their own users) can read the symlinks into ctx.app_dir.
    def upload_artifacts(ctx)
      ctx.rendered.each do |name, body|
        remote_path = "#{ctx.app_dir}/#{name}"
        b64 = [body].pack('m0')
        mode = name == '.env' ? '0600' : '0644'
        ctx.ssh.run(<<~SH, as: :deployer)
          install -d #{Shellwords.escape(File.dirname(remote_path))}
          echo #{Shellwords.escape(b64)} | base64 -d > #{Shellwords.escape(remote_path)}.new
          mv #{Shellwords.escape(remote_path)}.new #{Shellwords.escape(remote_path)}
          chmod #{mode} #{Shellwords.escape(remote_path)}
        SH
      end
    end

    def install_system_symlinks(ctx)
      ctx.ssh.run(<<~SH)
        install -d #{CADDY_SITES} #{SYSTEMD_DIR}
        ln -sfn #{Shellwords.escape(ctx.app_dir)}/systemd.service #{SYSTEMD_DIR}/lux-web-#{ctx.app}.service
        ln -sfn #{Shellwords.escape(ctx.app_dir)}/caddy.config    #{CADDY_SITES}/#{ctx.app}.caddy
      SH

      if ctx.job_template?
        ctx.ssh.run(<<~SH)
          ln -sfn #{Shellwords.escape(ctx.app_dir)}/systemd.job.service #{SYSTEMD_DIR}/lux-job-#{ctx.app}.service
        SH
      end
    end
  end

  # Bag of resolved state for a single command invocation.
  class Context
    attr_reader :host, :ssh, :branch, :app, :app_dir, :config_dir, :env_template_name, :yaml_config
    attr_accessor :port, :domain, :rendered

    def ruby_path
      @ruby_path ||= detect_ruby_path
    end

    # Yaml keys uppercased and symbolised, suitable for Template.render.
    # `server: foo` -> `{ SERVER: "foo" }`. Nil values are dropped so doctor's
    # placeholder check treats them as missing rather than blank.
    def yaml_vars
      @yaml_config.each_with_object({}) do |(k, v), h|
        next if v.nil?
        h[k.to_s.upcase.to_sym] = v.to_s
      end
    end

    # Base vars available to every template before .env is rendered:
    # git-derived + yaml. PORT/DIR/RUBY/RUBY_DIR are layered on top in
    # render_artifacts since they are only known after server probe.
    def base_vars
      Template.git_vars.merge(yaml_vars)
    end

    def self.load_yaml
      file = './config/deploy/.yaml'
      raise Error.new("missing #{file} (server: + domain: keys)") unless File.exist?(file)
      data = YAML.safe_load(File.read(file)) || {}
      raise Error.new("#{file} must be a YAML mapping") unless data.is_a?(Hash)
      data
    end

    def self.read_host(opts)
      override = opts[:server]
      return override.to_s.strip if override && !override.to_s.strip.empty?
      load_yaml['server'].to_s.strip.tap do |host|
        raise Error.new("config/deploy/.yaml: 'server:' is empty") if host.empty?
      end
    end

    def self.build(opts, render: true)
      ctx = new
      ctx.send(:resolve!, opts)
      ctx
    end

    def read_template(name)
      local = File.join(@config_dir, name)
      return File.read(local) if File.exist?(local)
      shipped = LuxDeploy::ROOT.join('templates', name).to_s
      return File.read(shipped) if File.exist?(shipped)
      raise Error.new("template not found: #{name} (looked in #{@config_dir} and #{shipped})")
    end

    def job_template?
      File.exist?(File.join(@config_dir, 'job.service'))
    end

    private

    def resolve!(opts)
      @config_dir = './config/deploy'
      raise Error.new("missing #{@config_dir}/ directory") unless Dir.exist?(@config_dir)

      @yaml_config = Context.load_yaml
      @host = (opts[:server].to_s.strip.empty? ? @yaml_config['server'].to_s : opts[:server]).strip
      raise Error.new("no server set (.yaml 'server:' or --server)") if @host.empty?

      @ssh    = SSH.new(@host, dry_run: opts[:dry_run] || false)
      @branch = Template.git_vars[:GIT_BRANCH]
      @env_template_name = LuxDeploy::MAIN_BRANCHES.include?(@branch) ? '.env' : '.env.staging'

      # App slug = result of rendering .env's DOMAIN, falling back to
      # yaml's `domain:` when .env doesn't redefine it. Render with stubs
      # for PORT/DIR/RUBY since we just need the DOMAIN line.
      preview_vars = base_vars.merge(PORT: 0, DIR: '/tmp/preview', RUBY: 'stub', RUBY_DIR: 'stub')
      preview = Template.render(read_template(@env_template_name), preview_vars)
      env = Template.parse_env(preview)
      raw = (env[:DOMAIN] || @yaml_config['domain']).to_s
      raise Error.new("no domain (.yaml 'domain:' or DOMAIN= in #{@env_template_name})") if raw.strip.empty?
      domain = raw.split(',').first.to_s.strip.sub(/^\*\./, '')
      raise Error.new('domain resolved to empty') if domain.empty?
      @app     = domain
      @domain  = domain
      @app_dir = File.join(LuxDeploy::REMOTE_BASE, domain)
    end

    def detect_ruby_path
      return '/home/deployer/.local/share/mise/installs/ruby/CURRENT/bin/ruby' if @ssh.dry_run
      out = @ssh.run(<<~SH, as: :deployer, allow_fail: true)
        ls -td ~/.local/share/mise/installs/ruby/*/bin/ruby 2>/dev/null | head -n1 || which ruby
      SH
      path = out.lines.find { |l| l.strip.start_with?('/') }&.strip
      raise Error.new('no ruby found on remote (mise not installed for deployer?)') if path.to_s.empty?
      path
    end
  end
end
