# RACK_ENV = test dev/development prod/production
#   live acts as production. RACK_ENV=live; Lux.env.prod? # true
# LUX_ENV  = lre - add any for dev env options. Emit all -> production settings
#   Lux.env.screen_log?   # true
#   Lux.env.reload_code?  # true
#
# lux s -p 3001-3003  # start 3 servers, auto-restart on failure after 5s

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
  method_option :port,  aliases: '-p', default: '3000', desc: 'Port or port range (e.g., 3001-3003)', type: :string
  method_option :env,   aliases: '-e', desc: 'Environment (test, dev, prod)'
  method_option :rerun, aliases: '-r', default: false, desc: 'Rerun app on every file change', type: :boolean
  method_option :opt,   aliases: '-o', default: 'lre', desc: 'Lux options (l=log, r=reload, e=errors)', type: :string
  def server
    trap("SIGINT") { Cli.die 'ctrl+c exit' }

    ENV['RACK_ENV'] = options[:env] if options[:env]
    ENV['LUX_ENV'] = options[:opt]

    # In development, always use port 3000 unless -p is explicitly given
    # In production, use PORT from .env or -p option
    is_production = ENV['RACK_ENV'].to_s.start_with?('p')
    port_option = if options[:port] != '3000'
      options[:port] # -p was explicitly given
    elsif is_production && ENV['PORT']
      ENV['PORT'] # production uses .env PORT
    else
      '3000' # development default
    end

    ports = parse_ports(port_option)
    base = "RACK_ENV=#{ENV['RACK_ENV']} LUX_ENV=#{ENV['LUX_ENV']} bundle exec puma"

    if ports.size > 1
      run_multi(base, ports)
    elsif options[:rerun]
      Cli.run "find #{LUX_ROOT} . -name *.rb | entr -r #{base} -p #{ports.first}"
    else
      Cli.run "#{base} -p #{ports.first}"
    end
  end

  private

  def parse_ports(port_arg)
    if port_arg.to_s.include?('-')
      start_port, end_port = port_arg.split('-').map(&:to_i)
      (start_port..end_port).to_a
    else
      [port_arg.to_i]
    end
  end

  def run_multi(base, ports)
    cmds = ports.map { |p| "(while true; do #{base} -p #{p}; echo 'Restarting port #{p} in 5s...'; sleep 5; done)" }
    system(cmds.join(' & ') + ' & wait')
  end
end
