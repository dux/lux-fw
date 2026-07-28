task :server do
  desc 'Start web server'
  alt :s
  opt :port,   alias: :p, desc: 'Port number'
  opt :env,    alias: :e, desc: 'Environment (development, test, production)'
  opt :rerun,  alias: :R, type: :boolean, default: false, desc: 'Rerun app on every file change'
  opt :debug,  alias: :d, type: :boolean, default: false, desc: 'Disable LUX_DEBUG (on by default on dev ports)'
  opt :reload, alias: :r, type: :boolean, default: false, desc: 'Disable LUX_RELOAD (on by default on dev ports)'

  proc do |opts|
    trap('SIGINT') { error 'ctrl+c exit' }

    port = (opts[:port] || ENV['PORT'] || 3000).to_i
    ENV['PORT'] = port.to_s

    # env: -e wins, else inherit the current LUX_ENV.
    if env = (opts[:env] || ENV['LUX_ENV'])
      ENV['LUX_ENV'] = env
    end

    # Only ever force the flags OFF here. Turning them ON is the per-env
    # default's job (Lux::Environment::Flags::FLAGS) - writing 'true' would
    # outrank it and was why `lux server -e test` ran with debug + reload on.
    # The port check is a CLI-layer heuristic and stays that way: a low port
    # means a privileged/public bind. The framework never looks at ports.
    off = port <= 500
    ENV['LUX_DEBUG']  = 'false' if off || opts[:debug]
    ENV['LUX_RELOAD'] = 'false' if off || opts[:reload]

    # " by ~/path/to/app" for the EADDRINUSE message: lsof gives the listening
    # pid, then that pid's cwd. Empty when lsof is missing or the process
    # belongs to another user - the message then reads as it always did.
    port_owner = lambda do |num|
      return '' unless Lux.shell.exists?('lsof')
      pid = Lux.shell.exec('lsof', '-nP', '-t', "-iTCP:#{num}", '-sTCP:LISTEN', timeout: 2) {}
      pid = pid.to_s.split("\n").first # clustered puma lists master + workers
      return '' unless pid
      cwd = Lux.shell.exec('lsof', '-a', '-p', pid, '-d', 'cwd', '-Fn', timeout: 2) {}
      cwd = cwd.to_s[/^n(.+)$/, 1]
      return '' unless cwd
      ' by %s' % cwd.sub(/\A#{Regexp.escape(Dir.home)}/, '~')
    end

    require 'socket'
    TCPServer.new('0.0.0.0', port).close

    # rename the terminal window/tab (ghostty, iterm2) for the server's lifetime
    print "\e]0;lux: #{File.basename(Dir.pwd)}\a" if $stdout.tty?

    # unset vars are skipped, otherwise puma would inherit LUX_DEBUG= (empty)
    # and the per-env default would never apply
    envs = %w(LUX_ENV LUX_DEBUG LUX_RELOAD).reject { ENV[_1].to_s.empty? }.map { "#{_1}=#{ENV[_1]}" }.join(' ')
    puma_cfg = File.exist?('config/puma.rb') ? '-C config/puma.rb' : ''
    base = "#{envs} bundle exec puma #{puma_cfg}".squeeze(' ')

    if opts[:rerun]
      sh "find #{LUX_ROOT} . -name *.rb | entr -r #{base} -p #{port}"
    else
      # replace the launcher with puma so no idle ruby process lingers
      exec "#{base} -p #{port}"
    end
  rescue Errno::EADDRINUSE
    Lux.shell.die 'Port %s is already in use%s' % [port, port_owner.(port)]
  end
end
