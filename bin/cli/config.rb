LuxCli.class_eval do
  desc :config, 'Show server config'
  method_option :mode,  aliases: '-m', default: 'production', desc: 'One of the server modes(dev, log, production)'
  def config
    require './config/application.rb'

    puts 'config:'
    Lux.config.sort.each do |key , value|
      value = case value
      when TrueClass
        'true'.green
      when FalseClass
        'false'.red
      when String
        "#{value.white}"
      when Proc
        'proc { ... }'
      else
        value
      end

      name = '  Lux.config.%s' % key.white
      print name.ljust(47)
      puts '= %s' % value
    end

    puts
    puts 'servers:'
    puts '  Lux.delay.server                  = %s' % Lux.delay.server
    puts '  Lux.cache.server                  = %s' % Lux.cache.server

    puts
    puts 'plugins:'
    Lux.plugin.keys.each do |key|
      puts '  Lux.plugin.%s - %s' % [key.ljust(22).white, Lux.plugin.get(key).folder]
    end

    Lux::Application.run_callback :info
  end
end
