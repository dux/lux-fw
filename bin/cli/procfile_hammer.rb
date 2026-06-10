task :procfile do
  desc 'Run all Procfile services color-prefixed; if one exits, stop them all'
  alt :pf
  opt :file, alias: :f, desc: 'Procfile path (default: ./Procfile)'

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

    colors = [36, 32, 33, 35, 34, 31, 96, 92, 95] # cyan, green, yellow, magenta, ...
    width  = services.map { |name, _| name.size }.max
    out    = Mutex.new
    procs  = {} # pid => name
    dying  = false

    # TERM every child's process group, once
    stop_all = lambda do
      next if dying
      dying = true
      procs.each_key { |pid| Process.kill('TERM', -pid) rescue nil }
    end

    %w[INT TERM].each { |sig| trap(sig) { stop_all.call } }

    services.each_with_index do |(name, cmd), i|
      label = format("\e[%dm%-#{width}s |\e[0m", colors[i % colors.size], name)
      reader, writer = IO.pipe
      pid = spawn(cmd, out: writer, err: writer, pgroup: true)
      writer.close
      procs[pid] = name

      # prefix each line of the child's merged stdout/stderr with its colored title
      Thread.new do
        reader.each_line { |ln| out.synchronize { $stdout.write "#{label} #{ln}" } }
      rescue IOError
        # pipe closed during shutdown
      end
    end

    # first service to exit takes the whole formation down
    dead = Process.wait
    say "\n#{procs[dead]} exited (#{$?.exitstatus}) - stopping all", :red
    stop_all.call
    Process.waitall
  end
end
