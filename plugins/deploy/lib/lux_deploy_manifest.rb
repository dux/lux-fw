module LuxDeploy
  module Manifest
    BASENAME ||= 'manifest.json'

    module_function

    def remote_path(path)
      "#{path}/#{BASENAME}"
    end

    def apps_root(service_user)
      "/home/#{service_user}/lux-apps"
    end

    def build(ctx)
      {
        app: ctx.app,
        service_user: ctx.service_user,
        ruby: ctx.ruby,
        host: ctx.config[:host],
        path: ctx.path,
        domain: ctx.config[:domain],
        port: ctx.port,
        db: { name: ctx.config.dig(:db, :name), user: ctx.config.dig(:db, :user) },
        systemd_units: ["lux-web-#{ctx.app}.service", "lux-job-#{ctx.app}.service"],
        caddy_site: "/etc/caddy/sites/#{ctx.app}.caddy",
        env_schema: env_schema(ctx.config[:env]),
        release: ctx.release,
        deployed_at: LuxDeploy.iso_now,
        ruby_path: "/home/#{ctx.service_user}/.local/share/mise/installs/ruby/#{ctx.ruby}/bin/ruby",
        bundle_path: ctx.bundle
      }
    end

    def write!(ctx)
      data = build(ctx)
      json = JSON.pretty_generate(data) + "\n"
      tmp = Dir.mktmpdir('lux-deploy-manifest')
      remote = remote_path(ctx.path)
      begin
        local = File.join(tmp, BASENAME)
        File.write(local, json)
        ctx.ssh.scp!(local, remote, category: :preflight)
        su = LuxDeploy.sh(ctx.service_user)
        ctx.ssh.ssh!("sudo chown #{su}:#{su} #{LuxDeploy.sh(remote)} && sudo chmod 0644 #{LuxDeploy.sh(remote)}",
                     category: :preflight, summary: 'cannot finalize manifest')
      ensure
        FileUtils.rm_rf(tmp) if tmp && Dir.exist?(tmp)
      end
    end

    def read(ssh, path)
      result = ssh.ssh("cat #{LuxDeploy.sh(path)}")
      return nil unless result.success?
      symbolize(JSON.parse(result.stdout))
    rescue JSON::ParserError
      nil
    end

    def list_paths(ssh, service_user)
      # `|| true` so an empty glob isn't a remote-shell error; the remote
      # command always exits 0 on a reachable host. SSH-layer failures
      # (host down, auth refused) keep their non-zero status and surface here.
      cmd = "ls -1 #{LuxDeploy.sh(apps_root(service_user))}/*/#{BASENAME} 2>/dev/null || true"
      result = ssh.ssh(cmd)
      unless result.success?
        raise CommandError.new(
          'cannot scan manifests on host',
          result,
          expected: "ssh #{ssh.host} reachable",
          need: 'SSH connection to deploy host',
          fix: "ssh #{ssh.host} true",
          category: :preflight
        )
      end
      result.stdout.lines.map(&:chomp).reject(&:empty?)
    end

    def read_all(ssh, service_user)
      list_paths(ssh, service_user).map { |path| [path, read(ssh, path)] }.reject { |_, m| m.nil? }
    end

    # Env schema records intent only — never resolved secret values.
    # true  -> 'required' (callers must export it locally)
    # false -> 'optional' (pass through if locally set)
    # else  -> 'literal'  (config-defined constant)
    def env_schema(env)
      env.each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = case value
                         when true then 'required'
                         when false then 'optional'
                         else 'literal'
                         end
      end
    end

    def symbolize(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize(v) }
      when Array then value.map { |v| symbolize(v) }
      else value
      end
    end
  end
end
