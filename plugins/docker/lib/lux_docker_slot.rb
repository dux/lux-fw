module LuxDocker
  # Two-slot side-by-side deploy. Each service with a configured even
  # `host_port` gets a paired slot at `host_port + 1`. The pair (N, N+1) holds
  # two equal slots; each deploy boots the new image on the sibling of the
  # currently-live slot, health-checks it in isolation, then flips Caddy to
  # point at the new port and stops the previous slot. The previous live
  # container stays running until the swap succeeds, giving zero-downtime and
  # one-step rollback.
  #
  # Each slot has its own Compose project name (`lux-<app>-<port>`) and its
  # own deploy env file (`config/docker/deploy.<port>.env`) so the two stacks
  # coexist without compose recreating either one.
  module Slot
    module_function

    def sibling(port)
      port.even? ? port + 1 : port - 1
    end

    # Resolve the target port for each service to the sibling of its
    # currently-live port (or the configured even port on first deploy).
    # Returns `{ service_name(String) => prev_port(Integer|nil) }` so the
    # caller can shut down the previous slot after a successful swap.
    #
    # Services without an explicit configured host_port (auto-allocated via
    # port_range) keep their existing host_port and skip slot semantics.
    # Staging deploys also skip - they are disposable, not blue/green.
    def resolve!(ctx)
      return {} if ctx.options[:staging]

      manifest = Manifest.read(ctx.ssh, Manifest.remote_path(ctx.path))
      prev_services = manifest ? manifest[:services] || {} : {}
      prev_ports = {}

      ctx.config[:services].each do |name, spec|
        configured = spec[:host_port]
        next unless configured
        next unless slottable?(spec)

        validate_even!(name, configured)

        prev_port = prev_services.dig(name.to_sym, :host_port) ||
                    prev_services.dig(name.to_s, :host_port)
        # Pin to the *configured* pair so a port_range change can't leak
        # a stale prev_port outside the current pair.
        target = if prev_port && [configured, configured + 1].include?(prev_port)
                   sibling(prev_port)
                 else
                   configured
                 end

        prev_ports[name.to_s] = prev_port if prev_port && prev_port != target
        spec[:host_port] = target
      end

      prev_ports
    end

    # Only web-style services (with domains served via caddy) participate in
    # the swap. Background workers without a port don't need it.
    def slottable?(spec)
      !!spec[:host_port] && Array(spec[:domains]).any?
    end

    def validate_even!(name, port)
      return if port.even?
      raise Error.new(
        "service #{name} host_port must be even",
        expected: 'even host_port (base of port pair used for blue/green swap)',
        current: "host_port=#{port}",
        need: 'set an even host_port; runtime uses (port, port+1) as live/test slots',
        fix: "edit services.#{name}.host_port in config/docker/deploy.json",
        category: :preflight
      )
    end

    def project_for(ctx, port)
      "lux-#{ctx.app}-#{port}"
    end

    def deploy_env_file_for(ctx, port)
      "#{ctx.path}/config/docker/deploy.#{port}.env"
    end

    # Apply slot identity to ctx: per-slot compose project + per-slot deploy
    # env file path so every subsequent Compose call targets the new slot.
    # Picks the live port from the first slottable service in the resolved
    # config; non-slottable services share the project.
    def apply_to_ctx!(ctx)
      port = ctx.config[:services]
                .each_value
                .map { |s| s[:host_port] if slottable?(s) }
                .compact
                .first
      return nil unless port
      ctx.config[:compose_project] = project_for(ctx, port)
      ctx.config[:deploy_env_path] = deploy_env_file_for(ctx, port)
      port
    end

    # Down + remove the slot project tied to a previous host_port. Tolerant:
    # if the previous slot is already gone, this is a no-op.
    def stop_slot!(ctx, port)
      return unless port
      env_file = deploy_env_file_for(ctx, port)
      project = project_for(ctx, port)
      head = Compose.shell(
        project: project,
        env_file: env_file,
        compose_files: Compose.remote_compose_files(ctx),
        cmd: ['down', '--remove-orphans']
      )
      ctx.ssh.ssh(head)
      # Best-effort cleanup of the now-unused per-slot env file.
      ctx.ssh.ssh("rm -f #{LuxDocker.sh(env_file)}")
    end

    # Best-effort discovery of every slot project on the host for this app -
    # used by `remove` to tear down both halves of the pair.
    def known_projects(ctx)
      result = ctx.ssh.ssh("docker compose ls --all --format json 2>/dev/null || true")
      return [] unless result.success?
      prefix = "lux-#{ctx.app}-"
      result.stdout.scan(/"Name":"([^"]+)"/).flatten.select { |n| n.start_with?(prefix) }
    end
  end
end
