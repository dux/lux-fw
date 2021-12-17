if ARGV[0] == 's'
  ARGV[0] = 'server'
elsif ARGV[0] == 'ss'
  # production mode with logging
  ARGV = %w{server -e log }
end

LuxCli.class_eval do
  ENVIRONEMNTS  = %w[production development test log]

  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', default: 3000,  desc: 'Port to run app on', type: :numeric
  method_option :env,   aliases: '-e', default: 'd',   desc: 'Environemnt, only first chart counts (%s)' % ENVIRONEMNTS.join(', ')
  method_option :rerun, aliases: '-r', default: false, desc: 'rerun app on every file chenge', type: :boolean
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    environemnt = options[:env]

    if environemnt.length == 1
      environemnt = ENVIRONEMNTS.find { |el| el[0] == environemnt[0] }
    end

    command = "puma -p #{options[:port]}"
    command = 'RACK_ENV=%s %s' % [environemnt, command]

    if options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{command}"
    else
      Cli.run command
    end
  end
end
