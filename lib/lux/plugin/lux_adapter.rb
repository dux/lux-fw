module Lux
  # simple interface to plugins
  # Lux.plugin :foo
  # Lux.plugin
  def plugin *args
    return ::Lux::Plugin if args.empty?

    for plugin_name in args
      folders = [Lux.root, Lux.fw_root].map { Pathname.new(_1).join('plugins', plugin_name.to_s) }
      root = folders.find(&:exist?)

      if root
        ::Lux::Plugin.load(root)
      else
        src = folders.map { _1.to_s }.join(', ')
        raise "Lux plugin #{plugin_name} not found in #{src}"
      end
    end
  end
end
