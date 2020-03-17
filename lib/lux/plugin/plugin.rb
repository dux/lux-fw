module Lux
  module Plugin
    extend self

    PLUGIN = {}

    # load specific plugin
    # Lux.plugin :foo
    # Lux.plugin 'foo/bar'
    # Lux.plugin.folders
    # Lux.plugin(:api).folder
    def load arg
      arg = arg.to_s if arg.is_a?(Symbol)

      if arg.is_a?(String)
        arg = arg.include?('/') ? { folder: arg } : { name: arg }
      end

      opts           = arg.to_ch [:name, :folder, :namespace]
      opts.name    ||= opts.folder.split('/').last
      opts.name      = opts.name.to_s
      opts.folder  ||= Lux.fw_root.join('plugins', opts.name).to_s
      opts.namespace = [opts.namespace] unless opts.namespace.is_a?(Array)

      return PLUGIN[opts.name] if PLUGIN[opts.name]

      die(%{Plugin "#{opts.name}" not found in "#{opts.folder}"}) unless Dir.exist?(opts.folder)

      PLUGIN[opts.name] ||= opts

      base = Pathname.new(opts.folder).join(opts.name, '.rb')

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
      list = PLUGIN.values
      list.select { |it| it.namespace.include?(namespace) }
      list.map { |it| it.folder }
    end
  end
end
