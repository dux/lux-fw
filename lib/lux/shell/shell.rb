require 'open3'
require 'shellwords'

module Lux
  # Lux::Shell - secure shell/process execution.
  #
  # argv mode is the default; the shell is never invoked unless `shell: true`
  # is passed explicitly. This makes injection-prone code visually obvious.
  #
  # Three entry points:
  #
  #   Lux.shell.exec('git', 'rev-parse', 'HEAD')          # stripped stdout
  #   Lux.shell.exec('bad') { |err, out| log err }        # block on failure -> nil
  #   Lux.shell.exec('bad') {}                            # silent on failure -> nil
  #   Lux.shell.exec('bad')                               # raises Lux::Shell::Error
  #
  #   Lux.shell.capture('bundle', 'install')              # merged stdout+stderr, never raises
  #
  #   Lux.shell.stream('rspec') { |line| puts line }      # yields lines, returns merged output
  #
  # Shortcut: Lux.shell(*argv, **opts, &block) delegates straight to exec.
  #
  # POSIX-only. Windows is not supported.
  module Shell
    extend self

    # Raised by Lux.shell.die when running in the test env, so failures can
    # be asserted on instead of exiting the suite.
    class Die < StandardError; end

    # Run a command. Returns stripped stdout on success.
    # On failure (non-zero exit, timeout, or ENOENT):
    #   * with a block: calls block.(stderr, stdout); returns nil
    #   * no block: raises Lux::Shell::Error
    #
    # opts:
    #   env:        Hash of env vars to merge into child env
    #   chdir:      working directory
    #   stdin_data: string piped into child stdin
    #   timeout:    seconds (nil = no timeout); timeout counts as failure
    #   shell:      pass through /bin/sh -c (single-string argv only)
    def exec *argv, env: {}, chdir: nil, stdin_data: nil, timeout: nil,
             shell: false, &block
      argv = argv.flatten.map(&:to_s)
      ::Kernel.raise ArgumentError, 'no command given' if argv.empty?
      spawn_argv = normalize_argv(argv, shell: shell)

      out, err, status, timed_out = capture3(env, spawn_argv,
        chdir: chdir, stdin_data: stdin_data, timeout: timeout)

      if !timed_out && status&.success?
        return out.strip
      end

      err = "timed out after #{timeout}s" if timed_out
      if block
        block.call(err, out)
        nil
      else
        ::Kernel.raise Lux::Shell::Error.new(argv, err, out)
      end
    end

    # Run a command and return the merged stdout+stderr output. Never raises;
    # exit status is discarded. Use when you want "everything that happened"
    # and intend to inspect / grep the buffer yourself.
    def capture *argv, env: {}, chdir: nil, stdin_data: nil, shell: false
      argv = argv.flatten.map(&:to_s)
      ::Kernel.raise ArgumentError, 'no command given' if argv.empty?
      spawn_argv = normalize_argv(argv, shell: shell)

      spawn_opts = {}
      spawn_opts[:chdir] = chdir if chdir
      collected = String.new
      Open3.popen2e(env, *spawn_argv, spawn_opts) do |stdin, io, wait_thr|
        stdin.write(stdin_data) if stdin_data
        stdin.close
        io.each { |chunk| collected << chunk }
        wait_thr.value
      end
      collected
    rescue Errno::ENOENT => e
      e.message
    end

    # Stream merged stdout+stderr line-by-line to the block. Returns the
    # collected merged output as a single string. Never raises on exit code.
    def stream *argv, env: {}, chdir: nil, shell: false, &block
      ::Kernel.raise ArgumentError, 'block required for stream' unless block
      argv = argv.flatten.map(&:to_s)
      ::Kernel.raise ArgumentError, 'no command given' if argv.empty?
      spawn_argv = normalize_argv(argv, shell: shell)

      collected  = String.new
      spawn_opts = {}
      spawn_opts[:chdir] = chdir if chdir

      Open3.popen2e(env, *spawn_argv, spawn_opts) do |stdin, io, wait_thr|
        stdin.close
        io.each_line do |line|
          collected << line
          block.call(line.chomp)
        end
        wait_thr.value
      end
      collected
    end

    # Absolute path to an executable on PATH, or nil.
    def which name
      name = name.to_s
      return (File.executable?(name) ? File.expand_path(name) : nil) if name.include?('/')
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, name)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    def exists? name
      !which(name).nil?
    end

    # Status output to STDERR (magenta). STDOUT stays clean for piping.
    # Accepts a string or an array of strings.
    def info text
      if text.is_a?(Array)
        text.each { |line| info line }
      else
        $stderr.puts '* %s' % text.to_s.colorize(:magenta)
      end
    end

    # Error output to STDERR (red).
    def error text
      if text.is_a?(Array)
        text.each { |line| error line }
      else
        $stderr.puts '! %s' % text.to_s.colorize(:red)
      end
    end

    # Log fatal, render to stderr and exit (1).
    # Accepts a string or an array. With an array the first entry is
    # the title and the rest are rendered as indented detail lines.
    # In test env, raises Lux::Shell::Die instead of exiting so callers
    # can assert on the error path with `must_raise`.
    def die text
      lines = Array(text).map(&:to_s)
      if app_line = Lux.app_caller
        lines << "at #{app_line}"
      end
      Lux.logger.fatal "Lux FATAL: #{lines.join(' | ')}" if Lux.mode.debug?

      if Lux.env.test?
        raise Lux::Shell::Die, lines.join(' | ')
      end

      $stderr.puts '! %s' % lines.first.colorize(:red)
      lines[1..].to_a.each { |line| $stderr.puts '  %s' % line.colorize(:red) }
      exit 1
    end

    private

    # shell:true wants a single string for /bin/sh -c. Reject multi-arg to
    # avoid silent surprise quoting.
    def normalize_argv argv, shell:
      return argv unless shell
      ::Kernel.raise ArgumentError, 'shell:true takes one string argv' if argv.length != 1
      [argv.first]
    end

    # Open3.capture3 with optional timeout. Returns [out, err, status, timed_out].
    def capture3 env, argv, chdir:, stdin_data:, timeout:
      spawn_opts = {}
      spawn_opts[:chdir] = chdir if chdir

      if timeout.nil?
        out, err, status = Open3.capture3(env, *argv, stdin_data: stdin_data.to_s, **spawn_opts)
        return [out, err, status, false]
      end

      out = String.new
      err = String.new
      status = nil
      timed_out = false

      Open3.popen3(env, *argv, spawn_opts) do |stdin, stdout, stderr, wait_thr|
        stdin.write(stdin_data) if stdin_data
        stdin.close

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        streams = [stdout, stderr]
        until streams.empty?
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            timed_out = true
            break
          end
          ready, = IO.select(streams, nil, nil, remaining)
          if ready.nil?
            timed_out = true
            break
          end
          ready.each do |io|
            begin
              chunk = io.readpartial(16384)
              (io.equal?(stdout) ? out : err) << chunk
            rescue EOFError
              streams.delete io
            end
          end
        end

        if timed_out
          begin Process.kill('KILL', wait_thr.pid); rescue Errno::ESRCH; end
        end
        status = wait_thr.value
      end

      [out, err, status, timed_out]
    rescue Errno::ENOENT => e
      [String.new, e.message, nil, false]
    end
  end
end
