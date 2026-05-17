module LuxDocker
  module Caddy
    SITES_DIR ||= '/etc/caddy/sites'.freeze

    module_function

    # Path on the host where the generated Caddyfile lives. Symlinked into
    # /etc/caddy/sites/<app>.caddy so Caddy imports follow the symlink.
    def app_caddyfile(ctx)
      "#{ctx.path}/Caddyfile"
    end

    def caddy_symlink(ctx)
      "#{SITES_DIR}/#{ctx.app}.caddy"
    end

    def render(ctx)
      tls = ctx.config[:tls]
      blocks = ctx.config[:services].map do |name, spec|
        next nil unless spec[:host_port]
        site_block(spec, name, tls)
      end.compact
      blocks.join("\n\n") + "\n"
    end

    def site_block(spec, name, tls = nil)
      domains = Array(spec[:domains]).join(', ')
      port = spec[:host_port]
      tls_block = tls_directive(spec, tls)
      # Block obvious scanner traffic at the edge. The web service gets the
      # heavier filter; other services (socket, admin) keep the shape simple.
      if name.to_s == 'web' || spec[:web]
        <<~CADDY.rstrip
          #{domains} {
          #{tls_block}    @blocked {
                  path *.php *.php5 *.phtml *.asp *.aspx *.jsp *.cgi
                  path /.env /.git /.git/* /wp-admin /wp-admin/* /wp-login.php
              }
              respond @blocked 404

              reverse_proxy 127.0.0.1:#{port}
          }
        CADDY
      else
        <<~CADDY.rstrip
          #{domains} {
          #{tls_block}    reverse_proxy 127.0.0.1:#{port}
          }
        CADDY
      end
    end

    # Emit a `tls { dns ... }` block when the profile configures DNS-01 or
    # any of this service's domains is a wildcard. Wildcards force DNS-01:
    # the validator already requires a tls block in that case.
    def tls_directive(spec, tls)
      return '' if tls.nil? || tls.empty?
      uses_wildcard = Array(spec[:domains]).any? { |d| d.to_s.start_with?('*.') }
      return '' unless uses_wildcard || tls[:always]
      [
        "    tls {",
        "        dns #{tls[:dns_provider]} {env.#{tls[:_caddy_env_key]}}",
        "    }",
        "",
        ""
      ].join("\n")
    end

    # Write the rendered Caddyfile to the app root, validate, then link it
    # into /etc/caddy/sites/<app>.caddy and reload.
    def install!(ctx)
      body = render(ctx)
      remote = app_caddyfile(ctx)
      tmp = Dir.mktmpdir('lux-deploy-caddy')
      file = File.join(tmp, "#{ctx.app}.caddy")
      File.write(file, body)
      ctx.ssh.scp!(file, remote, category: :caddy)
      ctx.ssh.ssh!("grep -qF 'import /etc/caddy/sites/*.caddy' /etc/caddy/Caddyfile || echo 'import /etc/caddy/sites/*.caddy' | sudo tee -a /etc/caddy/Caddyfile >/dev/null", category: :caddy, summary: 'cannot ensure caddy import')
      ctx.ssh.ssh!("sudo ln -sfn #{LuxDocker.sh(remote)} #{LuxDocker.sh(caddy_symlink(ctx))}", category: :caddy, summary: 'cannot symlink caddy site')
      install_tls_env!(ctx) if ctx.config[:tls]
      validate!(ctx)
      reload!(ctx)
    ensure
      FileUtils.rm_rf(tmp) if tmp && Dir.exist?(tmp)
    end

    # Ensure Caddy can read the DNS API token via `{env.<VAR>}`. Stores the
    # token in /etc/caddy/caddy.env (root:caddy 0640) and installs a systemd
    # drop-in pointing EnvironmentFile= at it. Upserts so multiple apps that
    # share a host can each contribute their own token line. The drop-in is
    # written once: daemon-reload + restart only on first install.
    def install_tls_env!(ctx)
      tls = ctx.config[:tls]
      key = tls[:_caddy_env_key]
      # Literal `api_token` in deploy.json wins; otherwise read from caller ENV
      # under the user-named `api_token_env`.
      token = tls[:api_token].to_s
      token = ENV[tls[:api_token_env].to_s].to_s if token.empty?
      env_file = '/etc/caddy/caddy.env'
      dropin = '/etc/systemd/system/caddy.service.d/lux.conf'

      existing = read_remote_env(ctx, env_file)
      existing[key] = token
      content = existing.map { |k, v| "#{k}=#{v}" }.sort.join("\n") + "\n"

      cmd = [
        'sudo install -d -m 0755 /etc/caddy',
        'sudo install -d -m 0755 /etc/systemd/system/caddy.service.d',
        "printf %s #{LuxDocker.sq(content)} | sudo tee #{env_file}.next >/dev/null",
        "sudo mv #{env_file}.next #{env_file}",
        "sudo chown root:caddy #{env_file} 2>/dev/null || sudo chown root:root #{env_file}",
        "sudo chmod 0640 #{env_file}",
        # Drop-in is idempotent: only daemon-reload + restart when first
        # written. Subsequent token edits are picked up by the reload! call
        # below (Caddy re-reads EnvironmentFile on reload).
        "if [ ! -f #{dropin} ]; then printf '%s\\n' '[Service]' 'EnvironmentFile=#{env_file}' | sudo tee #{dropin} >/dev/null && sudo systemctl daemon-reload && sudo systemctl restart caddy; fi"
      ].join(' && ')
      ctx.ssh.ssh!(cmd, category: :caddy, summary: 'cannot install caddy tls env')
    end

    # Best-effort parse of /etc/caddy/caddy.env. Tolerates missing files,
    # comment lines, and quoted values - we always rewrite the file from the
    # merged map below, so any quirky input quietly normalises.
    def read_remote_env(ctx, env_file)
      result = ctx.ssh.ssh("sudo cat #{env_file} 2>/dev/null || true")
      out = {}
      return out unless result.success?
      result.stdout.each_line do |line|
        line = line.chomp
        next if line.empty? || line.start_with?('#')
        k, v = line.split('=', 2)
        next unless k && v
        v = v[1..-2] if v.start_with?('"') && v.end_with?('"')
        out[k] = v
      end
      out
    end

    def validate!(ctx)
      ctx.ssh.ssh!('sudo caddy validate --config /etc/caddy/Caddyfile', category: :caddy, summary: 'caddy validate failed')
    end

    def reload!(ctx)
      ctx.ssh.ssh!('sudo systemctl reload caddy', category: :caddy, summary: 'caddy reload failed')
    end

    def remove!(ctx)
      ctx.ssh.ssh!("sudo rm -f #{LuxDocker.sh(caddy_symlink(ctx))}", category: :caddy, summary: 'cannot remove caddy symlink')
      reload!(ctx)
    end
  end
end
