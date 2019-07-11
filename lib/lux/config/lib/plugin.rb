module Lux::Config::Plugin
  extend self

  @plugins = {}

  # load specific plugin
  # Lux.plugin :foo
  # Lux.plugin 'foo/bar'
  # Lux.plugin.folders
  def load arg
    arg = arg.to_s if arg.is_a?(Symbol)

    if arg.is_a?(String)
      arg = arg.include?('/') ? { folder: arg } : { name: arg }
    end

    opts           = arg.to_opts name: String, folder: String, namespace: Symbol
    opts.name    ||= opts.folder.split('/').last
    opts.name      = opts.name.to_s
    opts.folder  ||= Lux.fw_root.join('plugins', opts.name).to_s
    opts.namespace = [opts.namespace] unless opts.namespace.is_a?(Array)

    return @plugins[opts.name] if @plugins[opts.name]

    die(%{Plugin "#{opts.name}" not found in "#{opts.folder}"}) unless Dir.exist?(opts.folder)

    @plugins[opts.name] ||= opts

    base = Pathname.new(opts.folder).join(opts.name, '.rb')

    if base.exist?
      require base.to_s
    else
      Lux.require_all(opts.folder)
    end

    @plugins[opts.name]
  end

  def get name
    @plugins[name.to_s] || die('Plugin "%s" not loaded' % name)
  end

  def loaded
     @plugins.values
  end

  def keys
    @plugins.keys
  end

  def plugins
    @plugins
  end

  # get all folders in a namespace
  def folders namespace=:main
    name = name.to_sym

    list = @plugins.values
    list.select { |it| it.namespace.include?(namespace) }
    list.map { |it| it.folder }
  end

end