ARGV[0] = 'server' if ARGV[0] == 's'

LuxCli.class_eval do
  desc :server, 'Start web server'
  method_option :port, type: :numeric, aliases: "-p", default: 3000, desc: 'Port to run app on'
  method_option :env, aliases: "-e", default: 'd', desc: 'Environemnt, only first chart counts'
  method_option :rerun, type: :boolean, aliases: "-r", default: false, desc: 'rerun app on every file chenge'
  def server
    flags = options[:env][0,1] == 'p' ? '' : 'ALL'
    flags = flags.upcase

    if options[:rerun]
      Cli.run "rerun -p '**/*.{rb,ru}' -d . -d #{LUX_ROOT} 'lux s -p #{options[:port]}'"
    else
      Cli.run "LUX_FLAGS=%s puma -p %s" % [flags, options[:port]]
    end
  end
end
