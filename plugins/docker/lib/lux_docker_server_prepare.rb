module LuxDocker
  # `lux docker:server:prepare` provisions a fresh host so subsequent
  # `lux docker:server:deploy` runs have everything they need. Every step
  # below is idempotent: rerunning the command on a fully-prepared host is
  # a sequence of no-ops with a clear log line per step.
  #
  # What it installs:
  #   * apt: docker, docker-compose-plugin, caddy, curl, rsync, git, ufw, xcaddy (if tls)
  #   * deployer service user + sudoers NOPASSWD
  #   * SSH hardening drop-in (password auth off, kbd-interactive off)
  #   * UFW: deny incoming, allow ssh-port + 80 + 443
  #   * Caddy: import line, sites dir, (xcaddy build with DNS provider if tls)
  #   * /home/deployer with 0711 + /home/deployer/lux-apps
  #   * Optional: postgres on 127.0.0.1, memcached on 127.0.0.1 (via --with)
  module ServerPrepare
    KNOWN_ADDONS ||= %w[postgres memcache].freeze

    module_function

    def run!(profile, opts)
      config = Config.resolve(profile, opts)
      addons = parse_with(opts[:with])
      ctx = Context.new(config, opts)

      ctx.step "server:prepare on #{config[:server]}"
      Preflight.ssh_who(ctx) # ensure we can reach the box

      step_apt!(ctx, addons)
      step_user!(ctx)
      step_sudo!(ctx)
      step_ssh_hardening!(ctx)
      step_ufw!(ctx)
      step_caddy_base!(ctx)
      step_caddy_dns!(ctx) if config[:tls]
      step_postgres!(ctx) if addons.include?('postgres')
      step_memcache!(ctx) if addons.include?('memcache')
      step_layout!(ctx)

      duration = LuxDocker.duration_since(ctx.started_at)
      puts "server:prepare ok #{config[:server]} addons=#{addons.empty? ? '-' : addons.join(',')} duration=#{duration}s"
    end

    def parse_with(value)
      Array(value).flat_map { |v| v.to_s.split(',') }.map(&:strip).reject(&:empty?).tap do |list|
        bad = list - KNOWN_ADDONS
        unless bad.empty?
          raise Error.new(
            'unknown server:prepare addon',
            expected: "addons in #{KNOWN_ADDONS.inspect}",
            current: "got #{bad.inspect}",
            need: 'use a supported addon',
            fix: "lux docker:server:prepare --with postgres,memcache",
            category: :preflight
          )
        end
      end
    end

    def step_apt!(ctx, addons)
      ctx.step 'apt install base packages'
      pkgs = %w[docker.io docker-compose-plugin caddy curl rsync git ufw]
      pkgs << 'postgresql' if addons.include?('postgres')
      pkgs << 'memcached' if addons.include?('memcache')
      pkgs << 'xcaddy' if ctx.config[:tls]
      ctx.ssh.ssh!(
        "DEBIAN_FRONTEND=noninteractive sudo -E apt-get update -qq && DEBIAN_FRONTEND=noninteractive sudo -E apt-get install -y -qq #{pkgs.join(' ')}",
        category: :preflight, summary: 'apt install failed'
      )
    end

    def step_user!(ctx)
      ctx.step "ensure service user #{ctx.service_user}"
      user = LuxDocker.sh(ctx.service_user)
      cmd = <<~SH
        id #{user} >/dev/null 2>&1 || sudo useradd --create-home --shell /bin/bash #{user}
        sudo usermod -aG docker #{user}
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: "cannot create user #{ctx.service_user}")
    end

    def step_sudo!(ctx)
      ctx.step "sudoers NOPASSWD for #{ctx.service_user}"
      user = LuxDocker.sh(ctx.service_user)
      path = "/etc/sudoers.d/lux-#{ctx.service_user}"
      cmd = <<~SH
        echo "#{ctx.service_user} ALL=(ALL) NOPASSWD:ALL" | sudo tee #{path} >/dev/null
        sudo chmod 0440 #{path}
        sudo visudo -c -f #{path} >/dev/null
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'sudoers install failed')
    end

    def step_ssh_hardening!(ctx)
      ctx.step 'ssh: enforce key-only auth'
      dropin = '/etc/ssh/sshd_config.d/10-lux.conf'
      body = "PasswordAuthentication no\nKbdInteractiveAuthentication no\n"
      cmd = <<~SH
        sudo install -d -m 0755 /etc/ssh/sshd_config.d
        printf %s #{LuxDocker.sq(body)} | sudo tee #{dropin} >/dev/null
        sudo chmod 0644 #{dropin}
        sudo sshd -t
        sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'ssh hardening failed')
    end

    def step_ufw!(ctx)
      ctx.step 'ufw: allow ssh + 80 + 443, deny rest'
      # Detect the active SSH port from sshd's resolved config so a
      # non-default port doesn't lock the operator out.
      port_cmd = "sudo sshd -T 2>/dev/null | awk '/^port / {print $2}' | head -n1"
      result = ctx.ssh.ssh(port_cmd)
      ssh_port = (result.success? && !result.stdout.strip.empty?) ? result.stdout.strip.to_i : 22
      ssh_port = 22 unless ssh_port.between?(1, 65_535)

      cmd = <<~SH
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow #{ssh_port}/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        echo y | sudo ufw enable >/dev/null
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'ufw configure failed')
    end

    def step_caddy_base!(ctx)
      ctx.step 'caddy: import line + sites dir'
      cmd = <<~SH
        sudo install -d -m 0755 /etc/caddy/sites
        grep -qF 'import /etc/caddy/sites/*.caddy' /etc/caddy/Caddyfile || echo 'import /etc/caddy/sites/*.caddy' | sudo tee -a /etc/caddy/Caddyfile >/dev/null
        sudo systemctl enable --now caddy
      SH
      ctx.ssh.ssh!(cmd, category: :caddy, summary: 'caddy base setup failed')
    end

    # If the deploy.json declares a `tls` block, rebuild caddy with the
    # matching caddy-dns plugin. Skipped when the plugin is already
    # present in `caddy list-modules`.
    def step_caddy_dns!(ctx)
      provider = ctx.config[:tls][:dns_provider]
      module_name = "dns.providers.#{provider}"
      check = ctx.ssh.ssh("caddy list-modules 2>/dev/null | grep -qx #{LuxDocker.sh(module_name)}")
      if check.success?
        ctx.step "caddy dns:#{provider} already installed"
        return
      end
      ctx.step "caddy dns:#{provider} build via xcaddy"
      cmd = <<~SH
        sudo xcaddy build --with github.com/caddy-dns/#{provider} --output /usr/bin/caddy
        sudo systemctl restart caddy
      SH
      ctx.ssh.ssh!(cmd, category: :caddy, summary: "xcaddy build of caddy-dns/#{provider} failed")
    end

    def step_postgres!(ctx)
      ctx.step 'postgres: listen on 127.0.0.1 only'
      cmd = <<~SH
        conf=$(ls /etc/postgresql/*/main/postgresql.conf 2>/dev/null | head -n1)
        if [ -z "$conf" ]; then
          echo "postgresql.conf not found" >&2
          exit 1
        fi
        sudo sed -i -E "s/^[#[:space:]]*listen_addresses[[:space:]]*=.*/listen_addresses = 'localhost'/" "$conf"
        grep -q "^listen_addresses" "$conf" || echo "listen_addresses = 'localhost'" | sudo tee -a "$conf" >/dev/null
        sudo systemctl restart postgresql
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'postgres lock-down failed')
    end

    def step_memcache!(ctx)
      ctx.step 'memcached: listen on 127.0.0.1 only'
      cmd = <<~SH
        sudo sed -i -E "s/^-l .*/-l 127.0.0.1/" /etc/memcached.conf
        grep -qE '^-l ' /etc/memcached.conf || echo "-l 127.0.0.1" | sudo tee -a /etc/memcached.conf >/dev/null
        sudo systemctl restart memcached
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'memcached lock-down failed')
    end

    def step_layout!(ctx)
      ctx.step "/home/#{ctx.service_user} chmod 0711 + lux-apps dir"
      su = LuxDocker.sh(ctx.service_user)
      home = LuxDocker.sh("/home/#{ctx.service_user}")
      root = LuxDocker.sh(ctx.config[:root])
      cmd = <<~SH
        sudo chmod 0711 #{home}
        sudo install -d -o #{su} -g #{su} -m 0755 #{root}
      SH
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'layout setup failed')
    end
  end

  module Commands
    module_function

    # Top-level entry: `lux docker:server:prepare`.
    def server_prepare(profile, opts = {})
      ServerPrepare.run!(profile, opts)
    end
  end
end
