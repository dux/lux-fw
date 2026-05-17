module LuxDeploy
  class SSH
    attr_reader :config, :dry_run, :quiet

    def initialize(config, dry_run: false, quiet: false)
      @config = config
      @dry_run = dry_run
      @quiet = quiet
    end

    def server
      config[:server]
    end

    def ssh(remote_cmd)
      run "ssh #{LuxDeploy.sh(server)} #{LuxDeploy.sq(remote_cmd)}"
    end

    def ssh!(remote_cmd, category: :unknown, summary: 'remote command failed')
      result = ssh(remote_cmd)
      return result if result.success?

      raise CommandError.new(
        summary,
        result,
        expected: "ssh #{server} #{remote_cmd.inspect} exits 0",
        need: 'remote command succeeds',
        fix: "ssh #{server} #{LuxDeploy.sq(remote_cmd)}",
        category: category
      )
    end

    def scp(local, remote)
      run "scp #{LuxDeploy.sh(local)} #{LuxDeploy.sh(server)}:#{LuxDeploy.sh(remote)}"
    end

    def scp!(local, remote, category: :source)
      result = scp(local, remote)
      return result if result.success?

      raise CommandError.new(
        'scp upload failed',
        result,
        expected: "scp to #{server}:#{remote} exits 0",
        need: 'remote path writable and SSH copy available',
        fix: "scp #{LuxDeploy.sh(local)} #{LuxDeploy.sh(server)}:#{LuxDeploy.sh(remote)}",
        category: category
      )
    end

    # Sync a local directory tree to remote, preserving its contents but
    # without the .gitignore/.git workarounds the old release flow needed.
    # Used for `config/docker/`, which is plain config the operator owns.
    #
    # When SSH user (e.g. root) differs from the service_user that owns the
    # app tree, files would land owned by root and later writes as service
    # user fail. Route the remote rsync through `sudo -u <service_user>` so
    # the destination files are created under the service user's identity.
    def rsync_to(src, remote)
      src = File.expand_path(src)
      src += '/' unless src.end_with?('/')
      parts = [
        'rsync -az --delete',
        '--exclude .git',
        '--exclude .DS_Store',
        # Per-slot deploy env files live only on the server (one per blue/green
        # slot). They are not in the local config/docker/ tree; without this
        # exclude `--delete` would wipe them and break old-slot teardown.
        "--exclude 'deploy.*.env'",
        # Image archive is shipped separately via scp; never sync it through.
        "--exclude 'images.tar.gz'"
      ]
      svc = config[:service_user].to_s
      parts << "--rsync-path=#{LuxDeploy.sq("sudo -u #{svc} rsync")}" unless svc.empty?
      parts << LuxDeploy.sh(src)
      parts << "#{LuxDeploy.sh(server)}:#{LuxDeploy.sh(remote)}/"
      run parts.join(' ')
    end

    def rsync_to!(src, remote, category: :source)
      result = rsync_to(src, remote)
      return result if result.success?

      raise CommandError.new(
        'rsync upload failed',
        result,
        expected: "rsync #{src} to #{server}:#{remote} exits 0",
        need: 'local source exists, remote path writable, and rsync installed on both ends',
        fix: "rsync -az #{LuxDeploy.sh(src)} #{LuxDeploy.sh(server)}:#{LuxDeploy.sh(remote)}/",
        category: category
      )
    end

    def run(cmd)
      LuxDeploy.run_local(cmd, dry_run: dry_run, quiet: quiet)
    end

    # Interactive ssh shell. Uses Kernel.system so the TTY stays attached -
    # Open3 buffers and won't.
    def shell(remote_cwd: nil)
      argv = ['ssh', '-t', server]
      argv << "cd #{LuxDeploy.sq(remote_cwd)} && exec \"${SHELL:-bash}\" -l" if remote_cwd
      puts "+ #{argv.join(' ')}" unless quiet
      return 0 if dry_run
      system(*argv)
      $?.exitstatus.to_i
    end
  end
end
