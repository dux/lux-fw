# Plugin layout (canonical):
#   plugins/<name>/
#     loader.rb     # OPTIONAL. Boot logic, required first.
#     load/         # OPTIONAL. All *.rb auto-required after loader.rb.
#     Hammerfile    # OPTIONAL. Single-file CLI tasks.
#     hammer/       # OPTIONAL. *_hammer.rb CLI tasks.
#     mount/        # OPTIONAL. Mirrors app root. `lux mount` symlinks
#                   # every leaf file into the app at the matching path.
#
# A plugin must have at least loader.rb or load/, otherwise it is empty.

module Lux
  module Plugin
    extend self

    PLUGIN ||= {}

    # Lux.plugin :foo
    # Lux.plugin 'foo/bar'
    # Lux.plugin.folders
    # Lux.plugin(:api).folder
    def load plugin_name
      plugin_name = Pathname.new(plugin_name) unless plugin_name.is_a?(Pathname)

      opts = { folder: plugin_name.to_s, name: plugin_name.basename.to_s }.to_hwia

      return PLUGIN[opts.name] if PLUGIN[opts.name]

      root = Pathname.new(opts.folder)

      die(%{Plugin "#{opts.name}" not found in "#{root}"}) unless root.directory?

      loader   = root.join('loader.rb')
      load_dir = root.join('load')

      unless loader.exist? || load_dir.directory?
        die(%{Plugin "#{opts.name}" has neither loader.rb nor load/ in "#{root}"})
      end

      PLUGIN[opts.name] ||= opts

      require loader.to_s            if loader.exist?
      Dir.require_all load_dir.to_s  if load_dir.directory?

      PLUGIN[opts.name]
    end

    def get name
      PLUGIN[name.to_s] || die('Plugin "%s" not loaded' % name)
    end

    def loaded
      PLUGIN.values
    end

    def loaded? name
      PLUGIN.key?(name.to_s)
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
