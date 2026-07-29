task :procfile do
  desc 'Run all Procfile services color-prefixed; if one exits, stop them all'
  alt :pf
  opt :file, alias: :f, desc: 'Procfile path (default: ./Procfile)'
  opt :kill_after, alias: :k, type: :integer, default: 5, desc: 'Seconds to wait after TERM before KILL'

  proc do |opts|
    file = opts[:file] || './Procfile'
    error "No Procfile at #{file}" unless File.exist?(file)

    # parse "name: command" lines, skip blanks and comments
    services = File.readlines(file).filter_map do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')
      name, cmd = line.split(/:\s*/, 2)
      [name, cmd] if cmd && !cmd.empty?
    end
    error "No services found in #{file}" if services.empty?

    colors   = [36, 32, 33, 35, 34, 31, 96, 92, 95] # cyan, green, yellow, magenta, ...
    width    = services.map { |name, _| name.size }.max
    grace    = opts[:kill_after].to_f
    out      = Mutex.new
    procs    = {} # live pid => name
    groups   = [] # every pgid we ever started
    stops    = 0  # how many times we have been asked to stop
    deadline = nil # when TERM turns into KILL

    # Signal a whole process group, then CONT it: a child parked in T state
    # (a background pgroup that touched the tty earns SIGTTIN) never runs its
    # TERM handler, and that is one of the ways a teardown hangs forever.
    signal_all = lambda do |sig|
      procs.each_key do |pid|
        Process.kill(sig, -pid) rescue nil
        Process.kill('CONT', -pid) rescue nil
      end
    end

    # Ask nicely once, escalate on the next Ctrl+C. Runs inside the trap on
    # purpose - the main loop can be parked in sleep, and having to wait for a
    # shutdown is the thing this is fixing.
    stop_all = lambda do
      stops += 1

      if stops > 1
        signal_all.call 'KILL'
      else
        deadline = Time.now + grace
        signal_all.call 'TERM'
      end
    end

    %w[INT TERM].each { |sig| trap(sig) { stop_all.call } }

    services.each_with_index do |(name, cmd), i|
      break if stops > 0 # Ctrl+C landed mid-startup

      label = format("\e[%dm%-#{width}s |\e[0m", colors[i % colors.size], name)
      reader, writer = IO.pipe

      # stdin detached - nothing in a Procfile is interactive, and a child that
      # reads the tty from its own process group stops rather than runs.
      pid = spawn(cmd, in: File::NULL, out: writer, err: writer, pgroup: true)
      writer.close
      procs[pid] = name
      groups << pid

      # prefix each line of the child's merged stdout/stderr with its colored title
      Thread.new do
        reader.each_line { |ln| out.synchronize { $stdout.write "#{label} #{ln}" } }
      rescue IOError
        # pipe closed during shutdown
      end
    end

    # a signal that arrived mid-spawn only reached the children that existed
    # then - repeat it rather than stop_all, which would escalate to KILL
    signal_all.call 'TERM' if stops > 0

    said   = false
    killed = false

    # First service to exit takes the whole formation down. Polled instead of
    # blocking on Process.wait so the KILL deadline still fires when every
    # remaining child is ignoring TERM - waitall simply never returns then.
    until procs.empty?
      pid = begin
        Process.wait(-1, Process::WNOHANG)
      rescue Errno::ECHILD
        break
      end

      if pid
        name   = procs.delete(pid)
        status = $?

        # only interesting when nobody asked for a shutdown yet
        if stops.zero?
          reason = status.termsig ? "killed by SIG#{Signal.signame(status.termsig)}" : "exited (#{status.exitstatus})"
          say "\n#{name} #{reason} - stopping all", :red
          said = true
          stop_all.call
        end

        next
      end

      if stops > 0
        unless said
          said = true
          say "\nstopping #{procs.values.join(', ')}", :yellow
        end

        if !killed && Time.now > deadline
          killed = true
          say "#{procs.values.join(', ')} ignored TERM - killing", :red
          signal_all.call 'KILL'
        end
      end

      sleep stops > 0 ? 0.1 : 0.5
    end

    # Reaping a group leader says nothing about the rest of its group, so sweep
    # whatever is left of every group we started. Only on a real teardown, to
    # keep the (tiny) pgid reuse window out of the happy path.
    if stops > 0
      groups.each do |pgid|
        Process.kill 0, -pgid
        Process.kill 'KILL', -pgid
      rescue SystemCallError
        # group is already gone, which is the point
      end
    end
  end
end
