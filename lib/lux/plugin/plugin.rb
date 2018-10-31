module Lux::Plugin
  extend self

  @plugins = {}

  def loader *args
    if [String, Symbol].include?(args.first.class)
      if args.first.to_s.include?('/')
        # cell can load plugin via
        # Lux.plugin __dir__
        parts = args.first.split('/')
        name  = parts.pop

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

    folder ||= Proc.new do
      folders = [Lux.fw_root.to_s, './lib', '.']
        .map { |f| f+'/plugins'}
        .map { |el| [el, name].join('/') }

       folders.find { |dir| Dir.exist?(dir) } ||
        die('Plugin %s not found, looked in %s' % [name, folders.map{ |el| "\n #{el}" }.join(', ')])
    end.call

    @plugins[name] ||= { namespace: namespace, folder: folder }

    base = '%s/%s.rb' % [name, folder]

    if File.exist?(base)
      load base
    else
      Lux::Config.require_all(folder)
    end
  end

  def get name
    data = @plugins[name.to_s] || die("Plugin %s not loaded")
    data.to_opts! :namespace, :folder
  end

  # get all name => folder hash for plugins in namespace
  def namespace name
    name = name.to_sym

    @plugins
      .select { |plugin| plugin[:namespace] == name }
      .map { |it| it[:folder] }
  end

  def keys
    @plugins.keys
  end

  # # Lux::Plugin.files 'city'
  # # Lux::Plugin.files 'city', ['js', 'coffee']
  # def files *args
  #   plugin = get args.shift
  #   files  = Dir["#{plugin[:folder]}/**/*"]

  #   if args.first
  #     types  = args.flatten.map(&:to_s)
  #     files.select { |it| types.include?(it.split('.').last) }
  #   else
  #     files
  #   end
  # end

end