if ARGV[0] == 's'
  ARGV[0] = 'server'
elsif ARGV[0] == 'ss'
  # production mode with logging
  ARGV = %w{server -m log }
end

LuxCli.class_eval do
  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', default: 3000,  desc: 'Port to run app on', type: :numeric
  method_option :mode,  aliases: '-m', default: nil,   desc: 'Mode: log (production mode with logging)'
  method_option :env,   aliases: '-e', default: 'd',   desc: 'Environemnt, only first chart counts'
  method_option :rerun, aliases: '-r', default: false, desc: 'rerun app on every file chenge', type: :boolean
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    environemnt = options[:env]

    if environemnt.length == 1
      environemnts  = %w[production development test]
      environemnt = environemnts.find { |el| el[0] == environemnt[0] }
    end

    command = "puma -p #{options[:port]} -e #{environemnt}"
    command = 'LUX_MODE=%s %s' % [options[:mode], command] if options[:mode]

    if options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{command}"
    else
      Cli.run command
    end
  end
end
