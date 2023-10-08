# no code reload with logging
# lux s -c

if ARGV[0] == 's'
  ARGV[0] = 'server'
end

if ARGV[0] == 'ss'
  ARGV[0] = 'server'
  ARGV[1] = '-f'
end

LuxCli.class_eval do
  ENVIRONEMNTS  = %w[production development test]

  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', default: 3000,  desc: 'Port to run app on', type: :numeric
  method_option :env,   aliases: '-e', default: 'd',   desc: 'Environemnt, only first chart counts (%s)' % ENVIRONEMNTS.join(', ')
  method_option :rerun, aliases: '-r', default: false, desc: 'rerun app on every file chenge', type: :boolean
  method_option :fast,  aliases: '-f', default: false, desc: 'prouction mode but dump errors', type: :boolean
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    command = []

    environemnt = options[:env]
    if environemnt.length == 1
      environemnt = ENVIRONEMNTS.find { |el| el[0] == environemnt[0] }
    end
    command.push 'RACK_ENV=%s' % environemnt

    ENV['LUX_DUMP_ERRORS'] = 'yes'
    ENV['LUX_LOG_CONSOLE'] = 'yes'
    
    for el in %w(code_reload dump_errors log_console log_disable)
      name = 'LUX_%s' % el.upcase
      ENV[name] ||= options[:fast] ? 'no' : 'yes'
      command.push "#{name}=#{ENV[name]}"
    end

    command = command.push("bundle exec puma -e #{environemnt}")
    command = command.join(' ')

    if options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{command}"
    else
      Cli.run command
    end
  end
end
