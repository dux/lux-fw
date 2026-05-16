define :config do
  desc 'Show server config'
  needs :app
  opt :mode, alias: :m, default: 'production', desc: 'One of the server modes (dev, log, production)'

  proc do |_opts|
    puts 'config:'
    Lux.config.sort.each do |key, value|
      value = case value
        when TrueClass  then 'true'.colorize(:green)
        when FalseClass then 'false'.colorize(:red)
        when String     then value.colorize(:white).to_s
        when Proc       then 'proc { ... }'
        else value.inspect
      end

      name = '  Lux.config.%s' % key.to_s.colorize(:white)
      print name.ljust(47)
      puts '= %s' % value
    end

    puts
    puts 'servers:'
    puts '  Lux.cache.server = %s' % Lux.cache.server

    puts
    puts 'plugins:'
    Lux.plugin.keys.each do |key|
      puts '  Lux.plugin.%s - %s' % [key.ljust(22).colorize(:white), Lux.plugin.get(key).folder]
    end
  end
end
