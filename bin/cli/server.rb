# no code reload with logging
# lux s -c

if ARGV[0] == 's'
  ARGV[0] = 'server'
end

LuxCli.class_eval do
  ENVIRONEMNTS  = %w[production development test]

  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', default: 3000,  desc: 'Port to run app on', type: :numeric
  method_option :env,   aliases: '-e', default: 'd',   desc: 'Environemnt, only first chart counts (%s)' % ENVIRONEMNTS.join(', ')
  method_option :rerun, aliases: '-r', default: false, desc: 'rerun app on every file chenge', type: :boolean
  method_option :code_reload, aliases: '-c', default: false, desc: 'no code reload', type: :boolean
  method_option :screen_log, aliases: '-l', default: false, desc: 'no screen log', type: :boolean
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    environemnt = options[:env]


    if environemnt.length == 1
      environemnt = ENVIRONEMNTS.find { |el| el[0] == environemnt[0] }
    end

    command = "puma -p #{options[:port]}"
    command = 'RACK_ENV=%s %s' % [environemnt, command]

    if options[:code_reload]
      command = 'LUX_CODE_RELOAD=no %s' % command
    end

    if options[:screen_log]
      command = 'LUX_SCREEN_LOG=no %s' % command
    end

    if options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{command}"
    else
      Cli.run command
    end
  end
end
