module LuxDeploy
  class SSH
    attr_reader :config, :dry_run, :quiet

    def initialize(config, dry_run: false, quiet: false)
      @config = config
      @dry_run = dry_run
      @quiet = quiet
    end

    def host
      config[:host]
    end

    def ssh(remote_cmd)
      run "ssh #{LuxDeploy.sh(host)} #{LuxDeploy.sq(remote_cmd)}"
    end

    def ssh!(remote_cmd, category: :unknown, summary: 'remote command failed')
      result = ssh(remote_cmd)
      return result if result.success?

      raise CommandError.new(
        summary,
        result,
        expected: "ssh #{host} #{remote_cmd.inspect} exits 0",
        need: 'remote command succeeds',
        fix: "ssh #{host} #{LuxDeploy.sq(remote_cmd)}",
        category: category
      )
    end

    def scp(local, remote)
      run "scp #{LuxDeploy.sh(local)} #{LuxDeploy.sh(host)}:#{LuxDeploy.sh(remote)}"
    end

    def scp!(local, remote, category: :source)
      result = scp(local, remote)
      return result if result.success?

      raise CommandError.new(
        'scp upload failed',
        result,
        expected: "scp to #{host}:#{remote} exits 0",
        need: 'remote path writable and SSH copy available',
        fix: "scp #{LuxDeploy.sh(local)} #{LuxDeploy.sh(host)}:#{LuxDeploy.sh(remote)}",
        category: category
      )
    end

    def rsync_to(src, remote)
      src = File.expand_path(src)
      src += '/' unless src.end_with?('/')
      cmd = [
        'rsync -az --delete',
        "--filter=#{LuxDeploy.sq(':- .gitignore')}",
        '--exclude .git',
        '--exclude .DS_Store',
        '--exclude tmp',
        '--exclude log',
        '--exclude node_modules',
        '--exclude coverage',
        LuxDeploy.sh(src),
        "#{LuxDeploy.sh(host)}:#{LuxDeploy.sh(remote)}/"
      ].join(' ')
      run cmd
    end

    def rsync_to!(src, remote)
      result = rsync_to(src, remote)
      return result if result.success?

      raise CommandError.new(
        'source sync failed',
        result,
        expected: "rsync #{src} to #{host}:#{remote} exits 0",
        need: 'local source exists, remote release dir writable, and rsync installed on both ends',
        fix: "lux deploy --src #{LuxDeploy.sh(src)} --host #{LuxDeploy.sh(host)} --app #{LuxDeploy.sh(config[:app])}",
        category: :source
      )
    end

    def run(cmd)
      LuxDeploy.run_local(cmd, dry_run: dry_run, quiet: quiet)
    end
  end
end
