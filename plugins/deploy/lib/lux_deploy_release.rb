module LuxDeploy
  module Release
    module_function

    def ensure_layout(ctx)
      path = LuxDeploy.sh(ctx.path)
      su = LuxDeploy.sh(ctx.service_user)
      cmd = [
        "sudo mkdir -p #{path}/releases #{path}/shared/log #{path}/shared/tmp",
        "sudo chown -R #{su}:#{su} #{path}"
      ].join(' && ')
      ctx.ssh.ssh!(cmd, category: :preflight, summary: 'cannot ensure release layout')
    end

    def create(ctx)
      ctx.release = LuxDeploy.now_ts
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, "mkdir -p #{release_path(ctx)}"),
                   category: :source, summary: 'cannot create release dir')
      ctx.release
    end

    def sync_source(ctx)
      if ctx.config[:branch]
        cmd = "git clone --branch #{LuxDeploy.sh(ctx.config[:branch])} --depth=1 #{LuxDeploy.sh(ctx.config[:repo])} #{release_path(ctx)}"
        ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd), category: :source, summary: 'git clone failed')
      else
        ctx.ssh.rsync_to!(ctx.config[:src], release_path(ctx))
        # rsync runs as the SSH user; normalize ownership to the service user.
        su = LuxDeploy.sh(ctx.service_user)
        ctx.ssh.ssh!("sudo chown -R #{su}:#{su} #{release_path(ctx)}",
                     category: :source, summary: 'cannot chown release to service user')
      end
    end

    def symlink_shared(ctx)
      cmd = [
        "mkdir -p #{LuxDeploy.sh(ctx.path)}/shared/log #{LuxDeploy.sh(ctx.path)}/shared/tmp",
        "cd #{release_path(ctx)}",
        'ln -sf ../../shared/.env .env',
        'rm -rf log tmp',
        'ln -s ../../shared/log log',
        'ln -s ../../shared/tmp tmp'
      ].join(' && ')
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :source, summary: 'cannot link shared release files')
    end

    def bundle_install(ctx)
      cmd = "cd #{release_path(ctx)} && #{LuxDeploy.sh(ctx.bundle)} install --deployment --without development test"
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :source, summary: 'bundle install failed')
    end

    def migrate(ctx)
      cmd = "cd #{release_path(ctx)} && #{LuxDeploy.sh(ctx.bundle)} exec lux db:am"
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :db, summary: 'database migration failed')
    end

    def swap_current(ctx)
      cmd = "cd #{LuxDeploy.sh(ctx.path)} && rm -f current.next && ln -s releases/#{ctx.release} current.next && mv -Tf current.next current"
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :systemd, summary: 'atomic current swap failed')
      Log.append(ctx, "swap current -> releases/#{ctx.release}")
    end

    def prune(ctx)
      cmd = "cd #{LuxDeploy.sh(ctx.path)}/releases && ls -1dt */ 2>/dev/null | sed -e 's#/##' | tail -n +3 | xargs -r rm -rf"
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :source, summary: 'release prune failed')
    end

    def rollback(ctx)
      releases_cmd = "cd #{LuxDeploy.sh(ctx.path)}/releases && ls -1dt */ 2>/dev/null | sed -e 's#/##' | sed -n '2p'"
      result = ctx.ssh.ssh(LuxDeploy.as_service_user(ctx, releases_cmd))
      prev = result.stdout.strip
      if prev.empty?
        raise Error.new(
          'nothing to roll back to',
          expected: 'at least two release directories exist',
          current: "no second release under #{ctx.path}/releases",
          need: 'deploy a previous release before rollback is possible',
          fix: "ssh #{ctx.config[:host]} 'ls -1dt #{ctx.path}/releases/*'",
          category: :systemd
        )
      end
      ctx.release = prev
      cmd = "cd #{LuxDeploy.sh(ctx.path)} && rm -f current.next && ln -s releases/#{prev} current.next && mv -Tf current.next current"
      ctx.ssh.ssh!(LuxDeploy.as_service_user(ctx, cmd),
                   category: :systemd, summary: 'rollback current swap failed')
      Log.append(ctx, "rollback current -> releases/#{prev}")
    end

    def release_path(ctx)
      "#{ctx.path}/releases/#{ctx.release}"
    end
  end
end
