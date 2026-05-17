require 'yaml'

module LuxDeploy
  # Named host checks: each entry is [label, check_cmd, fix_cmd_or_nil].
  # `check_cmd` must exit 0 on PASS, non-zero on FAIL.
  # `fix_cmd` is optional; if present and check fails, we run it (when --fix)
  # and re-check. Anything that needs interactive judgement leaves fix_cmd nil.
  module Doctor
    GREEN ||= "\e[32m"
    RED   ||= "\e[31m"
    DIM   ||= "\e[2m"
    RESET ||= "\e[0m"

    # Placeholders the plugin always provides at deploy time; templates
    # may reference these without declaring them in .env or config.yaml.
    PROVIDED_VARS ||= %w[GIT_BRANCH GIT_BRANCH_UNDERSCORE PORT DIR RUBY RUBY_DIR].freeze

    module_function

    def run(ssh, fix: true)
      puts 'Local config'
      local_failed = local_checks
      puts

      puts 'Remote host'
      checks = build_checks
      failed = local_failed

      checks.each do |label, check_cmd, fix_cmd|
        if passes?(ssh, check_cmd)
          puts "  #{GREEN}PASS#{RESET}  #{label}"
          next
        end

        if fix && fix_cmd
          puts "  #{DIM}FIX#{RESET}   #{label}"
          ssh.run(fix_cmd, allow_fail: true)
          if passes?(ssh, check_cmd)
            puts "  #{GREEN}PASS#{RESET}  #{label} (after fix)"
            next
          end
        end

        failed += 1
        puts "  #{RED}FAIL#{RESET}  #{label}"
        puts "  #{DIM}        check: #{check_cmd.lines.first.chomp}#{RESET}"
      end

      puts
      if failed.zero?
        puts "#{GREEN}all checks passed#{RESET}"
      else
        puts "#{RED}#{failed} check#{failed == 1 ? '' : 's'} failed#{RESET}"
        raise Error.new("doctor reported #{failed} failure(s)")
      end
    end

    # Run check command, return true on exit 0.
    def passes?(ssh, cmd)
      out = ssh.run(cmd + ' && echo __OK__ || echo __FAIL__', allow_fail: true)
      out.include?('__OK__')
    end

    # Verify every {{VAR}} inside caddy.conf / systemd.service / job.service
    # resolves from git vars + .env (or .env.staging). Returns failure count.
    def local_checks
      dir = './config/deploy'
      failed = 0

      report = ->(ok, label, detail = nil) {
        if ok
          puts "  #{GREEN}PASS#{RESET}  #{label}"
        else
          failed += 1
          puts "  #{RED}FAIL#{RESET}  #{label}"
          puts "  #{DIM}        #{detail}#{RESET}" if detail
        end
      }

      skip = ->(label) { puts "  #{DIM}SKIP  #{label} (does not exist)#{RESET}" }

      unless Dir.exist?(dir)
        report.call(false, "#{dir}/ directory present",
                    "missing; run: lux deploy:app:init")
        return failed
      end

      # Parse .yaml; bail early if absent or malformed since other
      # checks depend on its keys.
      yaml_path = "#{dir}/.yaml"
      yaml_data = nil
      if File.exist?(yaml_path)
        report.call(true, "#{yaml_path} present")
        begin
          yaml_data = YAML.safe_load(File.read(yaml_path)) || {}
          report.call(yaml_data.is_a?(Hash), "#{yaml_path} is a YAML mapping")
          yaml_data = {} unless yaml_data.is_a?(Hash)
          report.call(!yaml_data['server'].to_s.strip.empty?, ".yaml 'server:' set")
          report.call(!yaml_data['domain'].to_s.strip.empty?, ".yaml 'domain:' set")
        rescue Psych::SyntaxError => e
          report.call(false, "#{yaml_path} parses", e.message)
          yaml_data = {}
        end
      else
        report.call(false, "#{yaml_path} present", "missing; run: lux deploy:app:init")
        yaml_data = {}
      end

      report.call(File.exist?("#{dir}/.env"),            "#{dir}/.env present")
      report.call(File.exist?("#{dir}/caddy.conf"),      "#{dir}/caddy.conf present")
      report.call(File.exist?("#{dir}/systemd.service"), "#{dir}/systemd.service present")

      yaml_keys = yaml_data.keys.map { |k| k.to_s.upcase }

      env_keys = {}
      %w[.env .env.staging].each do |name|
        path = "#{dir}/#{name}"
        next unless File.exist?(path)
        env_keys[name] = File.read(path).scan(/^([A-Z][A-Z0-9_]*)=/).flatten
      end

      # Cross-check every placeholder in each template (including .env*).
      # yaml_keys are always provided; env_keys depend on which env template
      # is selected at deploy time, so we check each separately. .env.staging
      # and job.service are optional; skip with a note when absent.
      optional = %w[.env.staging job.service]
      placeholder_targets = %w[.env .env.staging caddy.conf systemd.service job.service]
      placeholder_targets.each do |name|
        path = "#{dir}/#{name}"
        unless File.exist?(path)
          skip.call(name) if optional.include?(name)
          next
        end

        placeholders = File.read(path).scan(Template::PLACEHOLDER).flatten.uniq

        # .env* templates can only reference vars provided BEFORE rendering;
        # other templates can also reference keys defined in the env itself.
        if name.start_with?('.env')
          provided = PROVIDED_VARS + yaml_keys
          missing  = placeholders - provided
          ok       = missing.empty?
          report.call(ok, "#{name}: placeholders resolve",
                      ok ? nil : "missing: #{missing.map { |v| "{{#{v}}}" }.join(' ')}")
        else
          env_keys.each do |env_name, keys|
            provided = PROVIDED_VARS + yaml_keys + keys
            missing  = placeholders - provided
            ok       = missing.empty?
            report.call(ok, "#{name}: placeholders resolve against #{env_name}",
                        ok ? nil : "missing: #{missing.map { |v| "{{#{v}}}" }.join(' ')}")
          end
        end
      end

      failed
    end

    def build_checks
      [
        [
          'deployer user exists',
          'id deployer >/dev/null 2>&1',
          'useradd -m -s /bin/bash deployer'
        ],
        [
          '/home/deployer is traversable (0755)',
          # caddy + systemd need to read symlinks into ~deployer/lux-apps;
          # useradd defaults /home/deployer to 0700 on Debian, which blocks them.
          "[ \"$(stat -c %a /home/deployer)\" = 755 ]",
          'chmod 0755 /home/deployer'
        ],
        [
          'deployer in sudo group (passwordless)',
          "grep -q '^deployer ' /etc/sudoers.d/deployer 2>/dev/null && grep -q NOPASSWD /etc/sudoers.d/deployer",
          "echo 'deployer ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/deployer && chmod 0440 /etc/sudoers.d/deployer"
        ],
        [
          '~/lux-apps exists and owned by deployer',
          "[ -d #{REMOTE_BASE} ] && [ \"$(stat -c %U #{REMOTE_BASE})\" = deployer ]",
          "install -d -o deployer -g deployer -m 0755 #{REMOTE_BASE}"
        ],
        [
          '/etc/caddy/sites exists',
          "[ -d #{CADDY_SITES} ]",
          "install -d -m 0755 #{CADDY_SITES}"
        ],
        [
          'caddy running',
          'systemctl is-active --quiet caddy',
          nil
        ],
        [
          "caddy imports #{CADDY_SITES}/*.caddy",
          "grep -Rq 'import #{CADDY_SITES}/\\*.caddy' /etc/caddy/ 2>/dev/null",
          nil
        ],
        [
          'mise installed for deployer',
          "sudo -iu deployer bash -lc 'command -v mise >/dev/null'",
          nil
        ],
        [
          'ruby on deployer PATH',
          "sudo -iu deployer bash -lc 'command -v ruby >/dev/null && ruby -v'",
          nil
        ],
        [
          'bundler on deployer PATH',
          "sudo -iu deployer bash -lc 'command -v bundle >/dev/null'",
          "sudo -iu deployer bash -lc 'gem install bundler --no-document'"
        ],
        [
          'xcaddy available (for plugin rebuilds)',
          'command -v xcaddy >/dev/null',
          nil
        ],
        [
          'ssh password auth disabled (warn-only)',
          "sshd -T 2>/dev/null | grep -qx 'passwordauthentication no'",
          nil
        ]
      ]
    end
  end
end
