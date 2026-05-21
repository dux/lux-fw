require 'open3'
require 'shellwords'

module Lux
  # Lux::Shell - secure, ergonomic shell/process execution.
  #
  # argv mode is the default; the shell is never invoked unless `shell: true`
  # is passed explicitly. This makes injection-prone code visually obvious.
  #
  #   Lux.shell.exec('git', 'status')
  #   Lux.shell.capture('git', 'rev-parse', 'HEAD')           # stdout string
  #   Lux.shell.run('bundle', 'exec', 'rspec')                # boolean
  #   Lux.shell.exec('curl', '-fsSL', url, timeout: 10)
  #   Lux.shell.exec('git', 'push', raise: true)
  #
  #   Lux.shell.exec('bad') { |r| Lux.logger.error r.err }    # block on failure
  #   Lux.shell.exec(cmd, on: :always) { |r| audit(r) }
  #
  # POSIX-only. Windows is not supported.
  module Shell
    extend self

    SHELL_UNSAFE ||= /[\s\$\`\\\;\|\&\>\<\*\?\!\(\)\[\]\{\}\'\"#~]/

    # Run a command. Returns a Lux::Shell::Result.
    #
    # opts:
    #   env:        Hash of env vars to merge into child env
    #   chdir:      directory to run in
    #   stdin_data: string written to child stdin
    #   timeout:    seconds (nil = no timeout)
    #   shell:      pass through /bin/sh -c (single-string argv only)
    #   raise:      raise Lux::Shell::Error on non-zero exit
    #   on:         block trigger - :failure (default), :success, :always
    def exec *argv, env: {}, chdir: nil, stdin_data: nil, timeout: nil,
             shell: false, raise: false, on: :failure, &block
      argv = argv.flatten.map(&:to_s)
      ::Kernel.raise ArgumentError, 'no command given' if argv.empty?

      if shell
        # shell mode joins everything into one string for /bin/sh -c.
        # If the caller passed multiple args, that almost always means
        # they meant argv mode - reject to avoid surprise quoting.
        ::Kernel.raise ArgumentError, 'shell:true takes one string argv' if argv.length != 1
        spawn_argv = [argv.first]
      else
        spawn_argv = argv
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      out, err, status, timed_out = capture3(env, spawn_argv,
        chdir: chdir, stdin_data: stdin_data, timeout: timeout)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      result = Result.new(
        command:   argv,
        out:       out,
        err:       err,
        status:    status,
        duration:  duration,
        timed_out: timed_out
      )

      if block
        case on
        when :failure then block.call(result) unless result.success?
        when :success then block.call(result) if result.success?
        when :always  then block.call(result)
        else ::Kernel.raise ArgumentError, "Unknown on: #{on.inspect} (use :failure, :success, :always)"
        end
      end

      ::Kernel.raise Lux::Shell::Error.new(result) if raise && !result.success?

      result
    end

    # Run and return stdout (stripped). Raises on failure unless a block is
    # passed (in which case the block decides whether to swallow).
    def capture *argv, **opts, &block
      opts = { raise: true }.merge(opts)
      opts[:raise] = false if block
      result = exec(*argv, **opts, &block)
      result.out.strip
    end

    # Run and return a boolean.
    def run *argv, **opts
      exec(*argv, **opts).success?
    end

    # Stream merged stdout+stderr line-by-line to the block.
    # Returns a Result with full collected output in .out.
    def stream *argv, env: {}, chdir: nil, shell: false, &block
      ::Kernel.raise ArgumentError, 'block required for stream' unless block
      argv = argv.flatten.map(&:to_s)
      ::Kernel.raise ArgumentError, 'no command given' if argv.empty?
      if shell
        ::Kernel.raise ArgumentError, 'shell:true takes one string argv' if argv.length != 1
        spawn_argv = [argv.first]
      else
        spawn_argv = argv
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      collected = String.new
      status = nil
      spawn_opts = {}
      spawn_opts[:chdir] = chdir if chdir
      Open3.popen2e(env, *spawn_argv, spawn_opts) do |stdin, io, wait_thr|
        stdin.close
        io.each_line do |line|
          collected << line
          block.call(line.chomp)
        end
        status = wait_thr.value
      end
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      Result.new(command: argv, out: collected, err: '', status: status,
                 duration: duration, timed_out: false)
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
    # Accepts a string or array of strings.
    def info text
      if text.class == Array
        text.each { |line| info line }
      else
        $stderr.puts '* %s' % text.to_s.colorize(:magenta)
      end
    end

    # Error output to STDERR (red).
    def error text
      if text.class == Array
        text.each { |line| error line }
      else
        $stderr.puts '! %s' % text.to_s.colorize(:red)
      end
    end

    # Log fatal and exit (1).
    def die text
      Lux.logger.fatal "Lux FATAL: #{text}"
      exit 1
    end

    private

    # Open3.capture3 with optional timeout. Returns [out, err, status, timed_out].
    def capture3 env, argv, chdir:, stdin_data:, timeout:
      spawn_opts = {}
      spawn_opts[:chdir] = chdir if chdir

      if timeout.nil?
        out, err, status = Open3.capture3(env, *argv, stdin_data: stdin_data.to_s, **spawn_opts)
        return [out, err, status, false]
      end

      # timeout path: drive stdout/stderr via IO.select and SIGKILL on expiry.
      out = String.new
      err = String.new
      status = nil
      timed_out = false

      Open3.popen3(env, *argv, spawn_opts) do |stdin, stdout, stderr, wait_thr|
        if stdin_data
          stdin.write stdin_data
        end
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
      [String.new, e.message, FakeStatus.new(127), false]
    end

    # Synthesized status for ENOENT (command not found). Matches the
    # public surface of Process::Status that callers actually use.
    class FakeStatus
      attr_reader :exitstatus
      def initialize(code) = @exitstatus = code
      def success?         = @exitstatus == 0
      def signaled?        = false
      def termsig          = nil
      def to_s             = "exit #{@exitstatus}"
      def inspect          = "#<FakeStatus exit=#{@exitstatus}>"
    end
  end
end
