module LuxDeploy
  module Systemd
    module_function

    def render(ctx)
      vars = {
        app: ctx.app,
        user: ctx.service_user,
        working_dir: "#{ctx.path}/current",
        bundle: ctx.bundle,
        port: ctx.port
      }
      {
        "lux-web-#{ctx.app}.service" => LuxDeploy.render_template('lux-web.service.erb', vars),
        "lux-job-#{ctx.app}.service" => LuxDeploy.render_template('lux-job.service.erb', vars)
      }
    end

    def install!(ctx)
      files = render(ctx)
      tmp = Dir.mktmpdir('lux-deploy-systemd')
      begin
        files.each { |name, body| File.write(File.join(tmp, name), body) }
        remote_dir = "#{Release.release_path(ctx)}/.sysd"
        ctx.ssh.ssh!("mkdir -p #{remote_dir}", category: :systemd, summary: 'cannot create systemd staging dir')
        files.each_key do |name|
          ctx.ssh.scp!(File.join(tmp, name), "#{remote_dir}/#{name}", category: :systemd)
        end
        install_cmd = "for f in #{remote_dir}/lux-*.service; do name=$(basename $f); if ! sudo test -f /etc/systemd/system/$name || ! sudo cmp -s $f /etc/systemd/system/$name; then changed=1; fi; done; if [ \"$changed\" = 1 ]; then sudo install -m 0644 #{remote_dir}/lux-*.service /etc/systemd/system/ && sudo systemctl daemon-reload; fi; sudo systemctl enable lux-web-#{ctx.app} lux-job-#{ctx.app}"
        ctx.ssh.ssh!(install_cmd, category: :systemd, summary: 'systemd unit install failed')
        # Files scp'd into the release dir may be root-owned when SSH'd as root;
        # normalize so service-user-run prune/rollback can unlink them.
        su = LuxDeploy.sh(ctx.service_user)
        ctx.ssh.ssh!("sudo chown -R #{su}:#{su} #{Release.release_path(ctx)}",
                     category: :systemd, summary: 'cannot chown release after systemd staging')
        Log.append(ctx, 'systemd install ok')
      ensure
        FileUtils.rm_rf(tmp) if tmp && Dir.exist?(tmp)
      end
    end

    def restart!(ctx)
      ctx.ssh.ssh!("sudo systemctl reload-or-restart lux-web-#{ctx.app} lux-job-#{ctx.app}", category: :systemd, summary: 'systemd restart failed')
      Log.append(ctx, 'reload systemd ok')
    end

    def uninstall!(ctx)
      ctx.ssh.ssh!("sudo systemctl stop lux-web-#{ctx.app} lux-job-#{ctx.app} 2>/dev/null || true", category: :systemd, summary: 'systemd stop failed')
      ctx.ssh.ssh!("sudo systemctl disable lux-web-#{ctx.app} lux-job-#{ctx.app} 2>/dev/null || true", category: :systemd, summary: 'systemd disable failed')
      ctx.ssh.ssh!("sudo rm -f /etc/systemd/system/lux-web-#{ctx.app}.service /etc/systemd/system/lux-job-#{ctx.app}.service && sudo systemctl daemon-reload", category: :systemd, summary: 'systemd unit remove failed')
    end

    def tail(config, lines: 100, follow: false, dry_run: false, quiet: false)
      app = config[:app]
      ssh = SSH.new(config, dry_run: dry_run, quiet: quiet)
      cmd = "sudo journalctl -u lux-web-#{app} -u lux-job-#{app} -n #{lines.to_i} --no-pager"
      cmd += ' -f' if follow
      result = ssh.ssh(cmd)
      print result.stdout unless result.stdout.empty?
      warn result.stderr unless result.stderr.empty?
      exit result.status unless result.success?
    end
  end
end
