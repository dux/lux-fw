module LuxDeploy
  module Log
    PATH ||= '/var/log/lux-deploy/deploy.log'

    module_function

    def append(ctx, message)
      line = "%s [%-10s] %s" % [LuxDeploy.iso_now, ctx.app, message]
      ctx.ssh.ssh!("mkdir -p /var/log/lux-deploy && printf '%s\\n' #{LuxDeploy.sq(line)} >> #{PATH}", category: :preflight, summary: 'cannot append deploy log')
    end

    def append_best_effort(ctx, message)
      append(ctx, message)
    rescue LuxDeploy::Error
      nil
    end

    def tail(config, lines: 50, app: nil, follow: false, dry_run: false, quiet: false)
      ssh = SSH.new(config, dry_run: dry_run, quiet: quiet)
      n = lines.to_i
      cmd = if follow && app
        "tail -n #{n} -F #{PATH} | grep --line-buffered #{LuxDeploy.sq("\\[#{app}\\]")}"
      elsif follow
        "tail -n #{n} -F #{PATH}"
      elsif app
        "grep #{LuxDeploy.sq("\\[#{app}\\]")} #{PATH} | tail -n #{n}"
      else
        "tail -n #{n} #{PATH}"
      end
      result = ssh.ssh(cmd)
      print result.stdout unless result.stdout.empty?
      warn result.stderr unless result.stderr.empty?
      exit result.status unless result.success?
    end
  end
end
