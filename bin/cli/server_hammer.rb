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

    # high (dev) ports default debug + reload on; -d / -r force them off.
    dev_default = port > 500
    ENV['LUX_DEBUG']  = (dev_default && !opts[:debug]).to_s
    ENV['LUX_RELOAD'] = (dev_default && !opts[:reload]).to_s

    require 'socket'
    TCPServer.new('0.0.0.0', port).close

    # rename the terminal window/tab (ghostty, iterm2) for the server's lifetime
    print "\e]0;#{File.basename(Dir.pwd)} lux web\a" if $stdout.tty?

    envs = %w(LUX_ENV LUX_DEBUG LUX_RELOAD).map { |k| "#{k}=#{ENV[k]}" }.join(' ')
    base = "#{envs} bundle exec puma"

    if opts[:rerun]
      sh "find #{LUX_ROOT} . -name *.rb | entr -r #{base} -p #{port}"
    else
      # replace the launcher with puma so no idle ruby process lingers
      exec "#{base} -p #{port}"
    end
  rescue Errno::EADDRINUSE
    Lux.shell.die 'Port %s is already in use' % port
  end
end
