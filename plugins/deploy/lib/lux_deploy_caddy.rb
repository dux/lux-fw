module LuxDeploy
  module Caddy
    module_function

    def install!(ctx)
      hash = basic_auth_hash(ctx)
      body = site_block(ctx, hash)
      remote = "/etc/caddy/sites/#{ctx.app}.caddy"
      tmp = Dir.mktmpdir('lux-deploy-caddy')
      file = File.join(tmp, "#{ctx.app}.caddy")
      File.write(file, body)
      ctx.ssh.scp!(file, remote, category: :caddy)
      ctx.ssh.ssh!("grep -qF 'import /etc/caddy/sites/*.caddy' /etc/caddy/Caddyfile || echo 'import /etc/caddy/sites/*.caddy' | sudo tee -a /etc/caddy/Caddyfile >/dev/null", category: :caddy, summary: 'cannot ensure caddy import')
      reload!(ctx)
      Log.append(ctx, 'caddy reload ok')
    ensure
      FileUtils.rm_rf(tmp) if tmp && Dir.exist?(tmp)
    end

    def remove!(ctx)
      ctx.ssh.ssh!("rm -f /etc/caddy/sites/#{ctx.app}.caddy", category: :caddy, summary: 'cannot remove caddy site block')
      reload!(ctx)
    end

    def reload!(ctx)
      ctx.ssh.ssh!("sudo systemctl reload caddy", category: :caddy, summary: 'caddy reload failed')
    end

    def basic_auth_hash(ctx)
      auth = ctx.config[:basic_auth]
      return nil unless auth

      user, pass = auth.split(':', 2)
      return [user, pass] if pass.start_with?('$2')

      # Pipe via stdin so the plaintext never appears in the remote process list.
      remote_cmd = "printf %s #{LuxDeploy.sq(pass)} | caddy hash-password"
      result = ctx.ssh.ssh(remote_cmd)
      unless result.success?
        raise CommandError.new(
          'basic auth password hashing failed',
          result,
          expected: 'caddy hash-password exits 0',
          need: 'caddy installed and password accepted by caddy',
          fix: "ssh #{ctx.config[:host]} #{LuxDeploy.sq(remote_cmd)}",
          category: :caddy
        )
      end
      [user, result.stdout.strip]
    end

    def site_block(ctx, auth)
      lines = []
      lines << "#{ctx.config[:domain]} {"
      if auth
        lines << '    basic_auth {'
        lines << "        #{auth[0]} #{auth[1]}"
        lines << '    }'
      end
      lines << "    reverse_proxy localhost:#{ctx.port}"
      lines << '}'
      lines << ''
      lines.join("\n")
    end
  end
end
