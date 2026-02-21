LuxCli.class_eval do
  desc :config, 'Show server config'
  method_option :mode,  aliases: '-m', default: 'production', desc: 'One of the server modes(dev, log, production)'
  def config
    require './config/app.rb'

    puts 'config:'
    Lux.config.sort.each do |key , value|
      value = case value
      when TrueClass
        'true'.colorize(:green)
      when FalseClass
        'false'.colorize(:red)
      when String
        "#{value.colorize(:white)}"
      when Proc
        'proc { ... }'
      else
        value.inspect
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
