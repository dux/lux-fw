task :server do
  desc 'Start web server'
  alt :s
  opt :port,   alias: :p, desc: 'Port number'
  opt :env,    alias: :e, desc: 'Environment (test, dev, prod)'
  opt :rerun,  alias: :R, type: :boolean, default: false, desc: 'Rerun app on every file change'
  opt :debug,  alias: :d, placeholder: 't/f', desc: 'LUX_DEBUG mode'
  opt :reload, alias: :r, placeholder: 't/f', desc: 'LUX_RELOAD mode'

  proc do |opts|
    trap('SIGINT') { error 'ctrl+c exit' }

    # t -> true, f -> false; otherwise pass-through (true/false accepted as-is).
    expand_mode = ->(v) { { 't' => 'true', 'f' => 'false' }[v.to_s.downcase] || v.to_s }

    ENV['RACK_ENV']   = opts[:env] if opts[:env]
    ENV['LUX_DEBUG']  = expand_mode.(opts[:debug])  if opts[:debug]
    ENV['LUX_RELOAD'] = expand_mode.(opts[:reload]) if opts[:reload]

    port = opts[:port] || ENV.fetch('PORT', '3000')
    ENV['PORT'] = port.to_s

    require 'socket'
    TCPServer.new('0.0.0.0', port.to_i).close

    # rename the terminal window/tab (ghostty, iterm2) for the server's lifetime
    print "\e]0;#{File.basename(Dir.pwd)} lux web\a" if $stdout.tty?

    flags = %w(LUX_DEBUG LUX_RELOAD).map { |k| "#{k}=#{ENV[k]}" }.join(' ')
    base  = "RACK_ENV=#{ENV['RACK_ENV']} #{flags} bundle exec puma"

    if opts[:rerun]
      sh "find #{LUX_ROOT} . -name *.rb | entr -r #{base} -p #{port}"
    else
      sh "#{base} -p #{port}"
    end
  rescue Errno::EADDRINUSE
    Lux.shell.die 'Port %s is already in use' % port
  end
end
