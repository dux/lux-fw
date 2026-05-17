require 'open3'
require 'shellwords'

module LuxDeploy
  # Always connects as root. To run as deployer pass `as: :deployer`
  # which wraps the command in `sudo -iu deployer bash -lc <quoted>`
  # so the login shell activates mise (PATH for ruby/bundler).
  class SSH
    attr_reader :host, :dry_run

    def initialize(host, dry_run: false)
      raise Error.new('config/deploy/server is empty') if host.to_s.strip.empty?
      @host = host.to_s.strip.sub(/^.*@/, '')
      @dry_run = dry_run
    end

    # Run a command. Returns stdout (always captured).
    # On non-zero exit raises unless allow_fail: true (then returns whatever was captured).
    def run(cmd, as: :root, allow_fail: false)
      remote = wrap(cmd, as)
      argv = ssh_argv + [remote]
      log argv, cmd
      return '' if dry_run
      out, status = Open3.capture2e(*argv)
      if !status.success? && !allow_fail
        raise Error.new("ssh failed (exit #{status.exitstatus})\n--- remote stderr+stdout ---\n#{out}")
      end
      out
    end

    # Streamed run (stdout/stderr pass through). Use for long-running steps
    # the user wants to watch (bundle install, smoke test).
    def stream(cmd, as: :root, allow_fail: false)
      remote = wrap(cmd, as)
      argv = ssh_argv + [remote]
      log argv, cmd
      return true if dry_run
      ok = system(*argv)
      raise Error.new("ssh failed: #{cmd}") if !ok && !allow_fail
      ok
    end

    # rsync local dir to remote path; runs receiver as deployer via sudo.
    def rsync(src, dest_path, excludes: [])
      argv = [
        'rsync', '-az', '--delete',
        *excludes.flat_map { |e| ['--exclude', e] },
        '--rsync-path=sudo -u deployer rsync',
        src, "root@#{host}:#{dest_path}"
      ]
      log argv, "rsync #{src} -> #{dest_path}"
      return if dry_run
      system(*argv) or raise Error.new('rsync failed')
    end

    # Interactive ssh that allocates a TTY and replaces the current process
    # (via Process.exec). Use for shells, REPLs, psql - anything that needs
    # job control. Does not return on success.
    def exec(cmd, as: :root)
      remote = wrap(cmd, as)
      argv = ssh_argv(interactive: true) + [remote]
      log argv, cmd
      return if dry_run
      Process.exec(*argv)
    end

    # scp a file from the remote (as root) to a local path.
    def scp_from(remote_path, local_path)
      argv = ['scp', '-o', 'StrictHostKeyChecking=accept-new',
              "root@#{host}:#{remote_path}", local_path]
      log argv, "scp #{remote_path} -> #{local_path}"
      return if dry_run
      system(*argv) or raise Error.new("scp failed: #{remote_path}")
    end

    private

    def ssh_argv(interactive: false)
      [
        'ssh',
        *(interactive ? ['-tt'] : ['-o', 'BatchMode=yes']),
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=10',
        "root@#{host}"
      ]
    end

    def wrap(cmd, as)
      case as
      when :root     then cmd
      when :deployer
        # sudo -i backslash-escapes every shell metachar including newlines, so
        # multi-line scripts get collapsed by the target shell (\<nl> = line
        # continuation). Transport the script base64-encoded so no metachars
        # survive into the deployer shell's re-parse.
        b64 = [cmd].pack('m0')
        inner = "echo #{b64} | base64 -d | bash -l"
        "sudo -iu deployer bash -lc #{Shellwords.escape(inner)}"
      else raise "unknown ssh user: #{as}"
      end
    end

    def log(_argv, summary)
      prefix = dry_run ? '  [dry] ' : '  $ '
      head = summary.lines.first.to_s.chomp
      head += ' …' if summary.lines.count > 1
      $stderr.puts "\e[2m#{prefix}#{head}\e[0m"
    end
  end
end
