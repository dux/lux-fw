module LuxDocker
  # Thin wrapper around `docker compose`. Builds argv with --project-name,
  # --env-file, and -f flags, so every call shells out in a way the operator
  # can copy/paste verbatim.
  module Compose
    module_function

    # argv head used for every docker compose invocation, locally or remotely
    def argv(project:, env_file:, compose_files:)
      args = ['docker', 'compose', '--project-name', project, '--env-file', env_file]
      Array(compose_files).each do |f|
        args << '-f'
        args << f
      end
      args
    end

    def shell(project:, env_file:, compose_files:, cmd:)
      (argv(project: project, env_file: env_file, compose_files: compose_files) + Array(cmd))
        .map { |s| LuxDocker.sh(s) }.join(' ')
    end

    # Resolve the remote compose argv head from a context. Used by every
    # remote `docker compose ...` step.
    def remote_argv(ctx)
      argv(
        project: ctx.config[:compose_project],
        env_file: deploy_env_path(ctx),
        compose_files: remote_compose_files(ctx)
      )
    end

    def remote_compose_files(ctx)
      ctx.config[:compose].map { |rel| "#{ctx.path}/#{rel}" }
    end

    # Slot-aware env file: each slot of the blue/green pair has its own
    # deploy.<port>.env so the two compose projects coexist on disk. Falls
    # back to the legacy single-slot deploy.env path when slot mode is off
    # (e.g. local test, or services without per-slot identity).
    def deploy_env_path(ctx)
      ctx.config[:deploy_env_path] || "#{ctx.path}/config/docker/deploy.env"
    end

    # Run a remote docker compose subcommand. `subcmd` is an array, e.g.
    # ['up', '-d', '--no-build', '--remove-orphans'].
    def run!(ctx, subcmd, category: :unknown, summary: 'docker compose failed')
      full = shell(
        project: ctx.config[:compose_project],
        env_file: deploy_env_path(ctx),
        compose_files: remote_compose_files(ctx),
        cmd: subcmd
      )
      ctx.ssh.ssh!(full, category: category, summary: summary)
    end

    def run(ctx, subcmd)
      full = shell(
        project: ctx.config[:compose_project],
        env_file: deploy_env_path(ctx),
        compose_files: remote_compose_files(ctx),
        cmd: subcmd
      )
      ctx.ssh.ssh(full)
    end

    def up!(ctx)
      run!(ctx, ['up', '-d', '--no-build', '--remove-orphans'],
           category: :compose, summary: 'docker compose up failed')
    end

    def down!(ctx, volumes: false)
      args = ['down', '--remove-orphans']
      args << '--volumes' if volumes
      run!(ctx, args, category: :compose, summary: 'docker compose down failed')
    end

    # Best-effort compose down for the current ctx slot. Used by the deploy
    # rollback path: a failed new slot should be torn down without masking
    # the original healthcheck error if the teardown itself fails.
    def down_quietly!(ctx)
      run(ctx, ['down', '--remove-orphans'])
    end

    def pull!(ctx)
      run!(ctx, ['pull'], category: :compose, summary: 'docker compose pull failed')
    end

    def config!(ctx)
      run!(ctx, ['config'], category: :compose, summary: 'docker compose config failed')
    end

    def ps(ctx)
      run(ctx, ['ps', '--format', 'json'])
    end

    # Build the local compose argv head for local build/test flows.
    def local_argv(config, env_file:)
      argv(
        project: config[:compose_project],
        env_file: env_file,
        compose_files: config[:compose].map { |rel| File.expand_path(rel, config[:app_root]) }
      )
    end

    # Project-local Postgres compose service is required for staging/PR
    # deploys unless explicitly skipped. Returns truthy if any compose file
    # declares a `services.db` block.
    def has_db_service?(config)
      config[:compose].any? do |rel|
        full = File.expand_path(rel, config[:app_root])
        content = File.read(full)
        # crude but adequate: matches `  db:` at start of a yaml line under services:
        content =~ /^\s{2,4}db:\s*$/
      end
    end

    # Ask docker compose itself which services exist, then ensure every
    # configured `compose_service` is present. Run as a remote check so the
    # answer reflects the same compose context the deploy will use.
    def verify_services!(ctx)
      result = run(ctx, ['config', '--services'])
      raise CommandError.new(
        'docker compose config --services failed',
        result,
        expected: 'compose config -q && --services exits 0',
        need: 'compose files parse on the host',
        fix: "ssh #{ctx.config[:server]} 'docker compose --project-name #{ctx.config[:compose_project]} --env-file #{deploy_env_path(ctx)} #{remote_compose_files(ctx).map { |f| "-f #{f}" }.join(' ')} config --services'",
        category: :compose
      ) unless result.success?

      present = result.stdout.lines.map(&:strip).reject(&:empty?)
      missing = ctx.config[:services].each_with_object([]) do |(name, spec), out|
        out << [name, spec[:compose_service]] unless present.include?(spec[:compose_service])
      end
      return if missing.empty?

      raise Error.new(
        'configured compose_service missing in compose files',
        expected: "every services.*.compose_service exists in compose config (#{present.join(', ')})",
        current: missing.map { |n, cs| "services.#{n}.compose_service=#{cs}" }.join(', '),
        need: 'add the missing service to compose.yml or fix services.*.compose_service',
        fix: "edit #{ctx.config[:compose].first}",
        category: :compose
      )
    end
  end
end
