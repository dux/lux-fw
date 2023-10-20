# RACK_ENV = test dev/development prod/production
#   live acts as production. RACK_ENV=live; Lux.env.prod? # true
# LUX_ENV  = clre - add any for dev env options. Emit all -> production settings
  # Lux.env.cache?
  # Lux.env.screen_log?
  # Lux.env.code_reload?
  # Lux.env.code_reload?

# no code reload with logging
# lux s -c

if ARGV[0] == 's'
  ARGV[0] = 'server'
end

# lux ss -> lux -opt le (only log and errors dump, no cacing and code reload)
if ARGV[0] == 'ss'
  ARGV[0] = 'server'
  $prod_in_dev = true
end

LuxCli.class_eval do
  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', default: 3000,  desc: 'Port to run app on', type: :numeric
  method_option :env,   aliases: '-e', default: 'development',   desc: 'Environemnt, only first chart counts (%s)'
  method_option :rerun, aliases: '-r', default: false, desc: 'rerun app on every file chenge', type: :boolean
  method_option :opt,  aliases: '-opt', default: 'clre', desc: 'lux options (clre - cache, screen log, code reload, errors)', type: :string
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    ENV['RACK_ENV'] = options[:env] if options[:env]
    ENV['LUX_ENV'] = options[:opt]
    ENV['LUX_ENV'] = 'le' if $prod_in_dev
    
    command = "RACK_ENV=#{ENV['RACK_ENV']} LUX_ENV=#{ENV['LUX_ENV']} bundle exec puma -p #{options[:port]}"

    if options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{command}"
    else
      Cli.run command
    end
  end
end
