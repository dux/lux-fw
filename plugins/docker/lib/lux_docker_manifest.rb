module LuxDocker
  module Manifest
    BASENAME ||= 'manifest.json'

    module_function

    def remote_path(path)
      "#{path}/#{BASENAME}"
    end

    def apps_root(root)
      root.to_s
    end

    def build(ctx)
      services = ctx.config[:services].each_with_object({}) do |(name, spec), out|
        out[name.to_s] = {
          compose_service: spec[:compose_service],
          host_port: spec[:host_port],
          container_port: spec[:container_port],
          domains: Array(spec[:domains])
        }
      end
      {
        app: ctx.app,
        server: ctx.config[:server],
        service_user: ctx.service_user,
        root: ctx.config[:root],
        path: ctx.path,
        compose_project: ctx.config[:compose_project],
        compose_files: Compose.remote_compose_files(ctx),
        staging: !!ctx.options[:staging],
        image_archive: "#{ctx.path}/config/docker/images.tar.gz",
        images: ctx.config[:images].each_with_object({}) { |(k, v), h| h[k.to_s] = v },
        caddyfile: Caddy.app_caddyfile(ctx),
        caddy_site: Caddy.caddy_symlink(ctx),
        services: services,
        env_schema: env_schema(ctx.config[:env]),
        volumes: Array(ctx.options[:volumes_track]),
        deployed_at: LuxDocker.iso_now
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
        su = LuxDocker.sh(ctx.service_user)
        ctx.ssh.ssh!("sudo chown #{su}:#{su} #{LuxDocker.sh(remote)} && sudo chmod 0644 #{LuxDocker.sh(remote)}",
                     category: :preflight, summary: 'cannot finalize manifest')
      ensure
        FileUtils.rm_rf(tmp) if tmp && Dir.exist?(tmp)
      end
    end

    def read(ssh, path)
      result = ssh.ssh("cat #{LuxDocker.sh(path)}")
      return nil unless result.success?
      symbolize(JSON.parse(result.stdout))
    rescue JSON::ParserError
      nil
    end

    def list_paths(ssh, root)
      cmd = "ls -1 #{LuxDocker.sh(apps_root(root))}/*/#{BASENAME} 2>/dev/null || true"
      result = ssh.ssh(cmd)
      unless result.success?
        raise CommandError.new(
          'cannot scan manifests on server',
          result,
          expected: "ssh #{ssh.server} reachable",
          need: 'SSH connection to deploy server',
          fix: "ssh #{ssh.server} true",
          category: :preflight
        )
      end
      result.stdout.lines.map(&:chomp).reject(&:empty?)
    end

    def read_all(ssh, root)
      list_paths(ssh, root).map { |path| [path, read(ssh, path)] }.reject { |_, m| m.nil? }
    end

    # Scan every other app's manifest on the host and refuse to deploy if a
    # domain or explicit host_port already belongs to a different app. Runs
    # after ensure_remote_layout! but before any state change.
    def verify_no_collisions!(ctx)
      others = read_all(ctx.ssh, ctx.config[:root]).reject { |_, m| m[:app].to_s == ctx.app.to_s }
      my_domains = ctx.config[:services].values.flat_map { |s| Array(s[:domains]) }
      my_ports = ctx.config[:services].values.map { |s| s[:host_port] }.compact
      others.each do |_, m|
        (m[:services] || {}).each do |name, spec|
          Array(spec[:domains]).each do |d|
            next unless my_domains.include?(d)
            raise Error.new(
              'domain already used by another app',
              expected: "#{d} unused",
              current: "owned by app=#{m[:app]} service=#{name}",
              need: 'use a different domain or remove the other deploy',
              fix: "lux docker:remove --app #{m[:app]}",
              category: :preflight
            )
          end
          next unless spec[:host_port]
          if my_ports.include?(spec[:host_port])
            raise Error.new(
              'host_port already used by another app',
              expected: "port #{spec[:host_port]} unused",
              current: "owned by app=#{m[:app]} service=#{name}",
              need: 'choose a different host_port',
              fix: "edit services.*.host_port",
              category: :preflight
            )
          end
        end
      end
    end

    # Env schema records intent only - never resolved secret values.
    # true       -> 'required' (callers must export it locally)
    # false/nil  -> 'optional' (pass through if locally set)
    # '$generate'-> 'generated' (per-app stable secret in shared/.env)
    # else       -> 'literal'  (config-defined constant)
    def env_schema(env)
      env.each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = case value
                         when true then 'required'
                         when false, nil then 'optional'
                         when Config::SECRET_GEN_TOKEN then 'generated'
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
