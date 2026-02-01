LuxCli.class_eval do
  desc :plugin, 'Show plugins or show plugin path'
  def plugin name = nil
    require './config/env'

    if name
      plugin = Lux::Plugin.get(name)
      puts plugin.folder
    else
      plugins = Lux::Plugin.loaded

      if plugins.empty?
        puts 'No plugins loaded'
      else
        puts 'Loaded plugins:'
        plugins.each do |p|
          puts "  #{p.name.ljust(20)} #{p.folder}"
        end
      end
    end
  end
end
