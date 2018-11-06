module Lux::Plugin
  extend self

  @plugins = {}

  def loader *args
    if [String, Symbol].include?(args.first.class)
      if args.first.to_s.include?('/')
        # cell can load plugin via
        # Lux.plugin __dir__
        parts = args.first.split('/')
        name  = parts.last

        load name: name, folder: parts.join('/')
      else
        # plain string is reference to name
        # Lux.plugin 'favicon'
        load name: args.first
      end
    else
      # pass arguents hash
      # Lux.plugin name: 'city', folder: './app/foo/bar'
      load *args
    end
  end

  # load specific plugin
  def load name:, folder: nil, namespace: :main
    name = name.to_s

    return if @plugins[name]

    folder ||= Lux.fw_root.join('plugins', name).to_s

    die(%{Plugin "#{name}" not found in "#{folder}"}) unless Dir.exist?(folder)

    @plugins[name] ||= { namespace: namespace, folder: folder }

    base = '%s/%s.rb' % [name, folder]

    if File.exist?(base)
      load base
    else
      Lux::Config.require_all(folder)
    end

    @plugins[name]
  end

  def get name
    data = @plugins[name.to_s] || die('Plugin "%s" not loaded' % name)
    data.to_opts! :namespace, :folder
  end

  def keys
    @plugins.keys
  end

  # get all name => folder hash for plugins in namespace
  def namespace name
    name = name.to_sym

    @plugins
      .select { |plugin| plugin[:namespace] == name }
      .map { |it| it[:folder] }
  end

end