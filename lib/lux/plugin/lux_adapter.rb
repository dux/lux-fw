module Lux
  # simple interface to plugins
  # Lux.plugin :foo        -> descriptor
  # Lux.plugin :foo, :bar  -> [descriptor, descriptor]
  # Lux.plugin             -> Lux::Plugin
  def plugin *args
    return ::Lux::Plugin if args.empty?

    names = ::Lux::Plugin.normalize_names(args)
    return if names.empty?

    descriptors = names.map { |name| ::Lux::Plugin.load_named(name) }
    names.length == 1 ? descriptors.first : descriptors
  end
end
