task :plugin do
  desc 'Show plugins or show plugin path'
  needs :env

  proc do |opts|
    name = opts[:args].first

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
