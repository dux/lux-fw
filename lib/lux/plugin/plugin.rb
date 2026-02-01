# define loader.rb in plugin folder for manual loader, loads all *.rb unless defined

module Lux
  module Plugin
    extend self

    PLUGIN = {}

    # load specific plugin
    # Lux.plugin :foo
    # Lux.plugin 'foo/bar'
    # Lux.plugin.folders
    # Lux.plugin(:api).folder
    def load plugin_name
      plugin_name = Pathname.new(plugin_name) unless plugin_name.is_a?(Pathname)

      opts = { folder: plugin_name.to_s, name: plugin_name.basename.to_s }.to_hwia

      return PLUGIN[opts.name] if PLUGIN[opts.name]

      die(%{Plugin "#{opts.name}" not found in "#{opts.folder}"}) unless Dir.exist?(opts.folder)

      PLUGIN[opts.name] ||= opts

      base = Pathname.new(opts.folder).join('loader.rb')

      if base.exist?
        require base.to_s
      else
        Dir.require_all(opts.folder)
      end

      PLUGIN[opts.name]
    end

    def get name
      PLUGIN[name.to_s] || die('Plugin "%s" not loaded' % name)
    end

    def loaded
       PLUGIN.values
    end

    def keys
      PLUGIN.keys
    end

    def plugins
      PLUGIN
    end

    # get all folders in a namespace
    def folders namespace=:main
      PLUGIN.values.map { |it| it.folder }
    end
  end
end
