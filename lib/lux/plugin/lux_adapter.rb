module Lux
  # simple interface to plugins
  # Lux.plugin :foo
  # Lux.plugin
  def plugin *args
    args.first ? ::Lux::Plugin.load(*args) : ::Lux::Plugin
  end
end
