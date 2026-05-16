require 'etc'
module LuxDeploy
  module Config
    APP_RE ||= /\A[a-z][a-z0-9_-]{0,62}\z/
    HOST_RE ||= /\A[A-Za-z0-9._@:\[\]-]+\z/
    DOMAIN_RE ||= /\A(\*\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/
    REPO_RE ||= /\A(https?:\/\/|git@)[a-zA-Z0-9.:\/_-]+(\.git)?\z/
    BRANCH_RE ||= /\A[A-Za-z0-9._\/-]{1,255}\z/
    DB_RE ||= /\A[a-z][a-z0-9_]{0,62}\z/
    ENV_KEY_RE ||= /\A[A-Z_][A-Z0-9_]*\z/
    BASIC_USER_RE ||= /\A[A-Za-z0-9._-]{1,64}\z/
    BASIC_PASS_RE ||= /\A[A-Za-z0-9._~+=,@%-]{1,256}\z/
    # POSIX-ish system username: lowercase or underscore start, then [a-z0-9_-].
    # Constrains shell expansions and matches `useradd` defaults.
    SERVICE_USER_RE ||= /\A[a-z_][a-z0-9_-]{0,31}\z/
    BCRYPT_RE ||= /\A\$2[aby]\$\d\d\$[\.\/A-Za-z0-9]{53}\z/
    # Postgres reserved/keyword words common enough to bite. Validation rejects
    # identifiers in this set so CREATE ROLE/DATABASE never breaks parsing.
    PG_RESERVED ||= %w[
      user select table default group order limit offset where from join
      grant revoke create drop alter index view database role public
      session current_user current_role primary foreign references
      check unique constraint cast collate when case then else end
      true false null and or not in like between is as on
    ].freeze

    module_function

    def resolve(profile, opts = {})
      profile = profile.to_s.empty? ? 'default' : profile.to_s
      app_root = find_app_root(Dir.pwd)
      config_path = opts[:config] ? File.expand_path(opts[:config]) : File.join(app_root, 'config/deploy.json')

      unless File.file?(config_path)
        raise Error.new(
          'deploy config not found',
          expected: "#{config_path} exists",
          current: "missing #{config_path}",
          need: 'create a deploy config or pass --config PATH',
          fix: "cp #{LuxDeploy.plugin_root.join('templates/deploy.json.example')} #{File.join(app_root, 'config/deploy.json')}",
          category: :preflight
        )
      end

      app = (opts[:app] || default_app_name(opts, app_root)).to_s
      if opts[:branch] && opts[:src]
        validation_error('--branch and --src are mutually exclusive', '--branch and --src are not passed together', 'both flags supplied', 'choose one source mode', 'remove --src or remove --branch')
      end
      if opts[:branch] && !opts[:app]
        validation_error('--branch requires --app', '--app supplied when deploying from git branch', '--branch supplied without --app', 'choose an app namespace', 'lux deploy --app myapp --repo URL --branch main')
      end

      data = JSON.parse(File.read(config_path))
      raw = resolve_profile(data, profile)
      raw = deep_merge(raw, cli_overlay(opts))
      raw['app'] = app
      raw['profile'] = profile
      raw['app_root'] = app_root
      raw['config_path'] = config_path
      raw['src'] ||= opts[:branch] ? nil : File.expand_path(opts[:src] || Dir.pwd)
      raw['db'] ||= {}
      raw['db']['name'] ||= app.tr('-', '_')
      raw['healthcheck'] ||= {}
      raw['healthcheck']['path'] ||= '/'
      raw['healthcheck']['timeout'] ||= 30
      raw['healthcheck']['expect_status'] ||= [200, 201, 204, 301, 302]

      load_lux_env(app_root) if contains_config_placeholder?(raw)
      resolved = interpolate(raw, raw)
      normalized = symbolize(resolved)
      normalized[:app_underscored] = normalized[:app].tr('-', '_')
      normalized[:env] ||= {}
      normalized[:db] ||= {}
      normalized[:user] = ssh_user_hint(normalized[:host])
      normalized[:service_user] ||= 'deployer'
      normalized[:db][:user] ||= normalized[:service_user]
      normalized[:port] = normalized[:port].to_i if normalized[:port]
      normalized[:basic_auth] = opts[:basic_auth] if opts.key?(:basic_auth)
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

    def default_app_name(opts, app_root)
      if opts[:branch]
        nil
      elsif opts[:src]
        File.basename(File.expand_path(opts[:src]))
      else
        File.basename(Dir.pwd)
      end
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

    def cli_overlay(opts)
      overlay = {}
      %i[host path domain port repo branch ruby basic_auth service_user].each do |key|
        overlay[key.to_s] = opts[key] if opts.key?(key) && !opts[key].nil?
      end
      if opts[:db_name] || opts[:db_user]
        overlay['db'] = {}
        overlay['db']['name'] = opts[:db_name] if opts[:db_name]
        overlay['db']['user'] = opts[:db_user] if opts[:db_user]
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
          current = current.gsub(/\{\{([^}]+)\}\}/) { lookup_placeholder(Regexp.last_match(1).strip, root) }
        end
        if current.match?(/\{\{[^}]+\}\}/)
          raise Error.new(
            'unresolved placeholder in deploy config',
            expected: 'all {{...}} placeholders resolve to strings',
            current: current,
            need: 'define the referenced value or remove the placeholder',
            fix: root['config_path'].to_s,
            category: :preflight
          )
        end
        current
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
          expected: '{{app}}, {{app_underscored}}, {{profile}}, or {{config.*}}',
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

    def ssh_user_hint(host)
      host.to_s.include?('@') ? host.to_s.split('@', 2).first : Etc.getlogin || ENV['USER'] || 'deploy'
    end

    def validate!(config)
      validate_match(:app, config[:app], APP_RE)
      validate_match(:host, config[:host], HOST_RE)
      validate_path(config[:path])
      validate_src(config[:src]) if config[:src]
      validate_domains(config[:domain]) if config[:domain]
      validate_port(config[:port]) if config[:port]
      validate_match(:ruby, config[:ruby], /\A[0-9A-Za-z._-]+\z/)
      validate_match(:repo, config[:repo], REPO_RE) if config[:repo]
      validate_match(:branch, config[:branch], BRANCH_RE) if config[:branch]
      validate_match(:service_user, config[:service_user], SERVICE_USER_RE)
      validate_match(:db_name, config.dig(:db, :name), DB_RE)
      validate_match(:db_user, config.dig(:db, :user), DB_RE)
      validate_pg_identifier(:db_name, config.dig(:db, :name))
      validate_pg_identifier(:db_user, config.dig(:db, :user))
      validate_basic_auth(config[:basic_auth]) if config[:basic_auth]
      validate_env(config[:env])
      validate_healthcheck(config[:healthcheck])
      true
    end

    def validate_pg_identifier(name, value)
      return unless PG_RESERVED.include?(value.to_s.downcase)
      validation_error(
        "invalid #{name}",
        "#{name} is not a Postgres reserved word",
        "#{name}=#{value.inspect}",
        'rename to a non-reserved identifier',
        "edit config/deploy.json or pass --#{name.to_s.tr('_', '-')} VALUE"
      )
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

    def validate_path(path)
      ok = path.to_s.start_with?('/') && !path.to_s.include?('..') && !path.to_s.match?(/[\s;&|`$<>\\]/)
      validation_error('invalid path', 'absolute path with no spaces, .., or shell metacharacters', "path=#{path.inspect}", 'provide a safe absolute deploy path', 'pass --path /var/www/myapp') unless ok
    end

    def validate_src(src)
      return if File.directory?(src)

      validation_error('invalid src', 'local --src path exists and is a directory', "src=#{src.inspect}", 'provide a deploy source directory', 'pass --src .')
    end

    def validate_domains(value)
      value.to_s.split(',').each do |domain|
        next if domain.match?(DOMAIN_RE)
        validation_error('invalid domain', 'each domain matches deploy domain rules', "domain=#{domain.inspect}", 'provide DNS-safe lowercase domains', 'pass --domain example.com')
      end
    end

    def validate_port(port)
      ok = port.is_a?(Integer) && port.between?(1024, 65_535)
      validation_error('invalid port', 'integer in 1024-65535', "port=#{port.inspect}", 'provide an unprivileged TCP port', 'pass --port 3142') unless ok
    end

    def validate_basic_auth(value)
      user, pass = value.to_s.split(':', 2)
      ok = user && pass && user.match?(BASIC_USER_RE) && (pass.match?(BASIC_PASS_RE) || pass.match?(BCRYPT_RE))
      validation_error('invalid basic-auth', 'user:pass with deploy-safe username and password', "basic_auth=#{value.inspect}", 'provide a safe basic auth credential', 'pass --basic-auth user:password') unless ok
    end

    def validate_env(env)
      env.each do |key, value|
        validate_match(:env_key, key, ENV_KEY_RE)
        if value.is_a?(String) && value.include?("\0")
          validation_error('invalid env value', 'env values contain no embedded NUL', "#{key} contains NUL", 'remove NUL bytes from env value', "edit env #{key}")
        end
      end
    end

    def validate_healthcheck(hash)
      path = hash[:path].to_s
      unless path.start_with?('/') && !path.match?(/[\s;&|`$<>\\]/)
        validation_error('invalid healthcheck path', 'path starts with / and has no shell metacharacters', "path=#{path.inspect}", 'provide a safe HTTP path', 'edit healthcheck.path')
      end
      timeout = hash[:timeout].to_i
      hash[:timeout] = timeout
      statuses = Array(hash[:expect_status]).map(&:to_i)
      hash[:expect_status] = statuses
    end

    def validation_error(summary, expected, current, need, fix)
      raise Error.new(summary, expected: expected, current: current, need: need, fix: fix, category: :preflight)
    end
  end
end
