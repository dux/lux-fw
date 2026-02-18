# RACK_ENV = test dev/development prod/production
#   live acts as production. RACK_ENV=live; Lux.env.prod? # true
# LUX_ENV  = lre - add any for dev env options. Emit all -> production settings
#   Lux.env.screen_log?   # true
#   Lux.env.reload_code?  # true
#
# PORT=3000  # defaults to 3000

# Shortcuts: lux s, lux ss, lux silent
case ARGV[0]
when 's'
  ARGV[0] = 'server'
when 'ss' # only log and errors dump, no code reload
  ARGV[0..0] = ['server', '-o', 'le']
when 'silent' # no screen logging
  ARGV[0..0] = ['server', '-o', 're']
end

LuxCli.class_eval do
  desc :server, 'Start web server'
  method_option :port,  aliases: '-p', desc: 'Port number', type: :string
  method_option :env,   aliases: '-e', desc: 'Environment (test, dev, prod)'
  method_option :rerun, aliases: '-r', default: false, desc: 'Rerun app on every file change', type: :boolean
  method_option :opt,   aliases: '-o', default: 'lre', desc: 'Lux options (l=log, r=reload, e=errors)', type: :string
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    ENV['RACK_ENV'] = options[:env] if options[:env]
    ENV['LUX_ENV'] = options[:opt]

    port = options[:port] || ENV.fetch('PORT', '3000')
    ENV['PORT'] = port.to_s

    base = "RACK_ENV=#{ENV['RACK_ENV']} LUX_ENV=#{ENV['LUX_ENV']} bundle exec puma"

    if options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{base} -p #{port}"
    else
      Cli.run "#{base} -p #{port}"
    end
  end
end
