if ARGV[0] == 's'
  ARGV[0] = 'server'
elsif ARGV[0] == 'ss'
  # production mode with logging
  ARGV = %w{server -m log }
end

LuxCli.class_eval do
  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', default: 3000,  desc: 'Port to run app on', type: :numeric
  method_option :mode,  aliases: '-m', default: 'dev', desc: 'One of the server modes(dev, log, production)'
  method_option :env,   aliases: '-e', default: 'd',   desc: 'Environemnt, only first chart counts'
  method_option :rerun, aliases: '-r', default: false, desc: 'rerun app on every file chenge', type: :boolean
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    mode  = 'LUX_MODE=%s' % options[:mode]
    env   = options[:env][0,1] == 'p' ? 'production' : 'development'

    if options[:rerun]
      Cli.run "#{mode} rerun -p '**/*.{rb,ru}' -d . -d #{LUX_ROOT} 'lux s -p #{options[:port]}'"
    else
      Cli.run "#{mode} puma -e #{env} -p #{options[:port]}"
    end
  end
end
