module Lux
  # simple interface to plugins
  # Lux.plugin :foo
  # Lux.plugin
  def plugin *args
    return ::Lux::Plugin if args.empty?

    names = ::Lux::Plugin.normalize_names(args)
    return if names.empty?

    result = nil
    queue  = names.dup
    seen   = {}

    while plugin_name = queue.shift
      next if seen[plugin_name]

      seen[plugin_name] = true
      before = ::Lux::Plugin.normalize_names(Lux.config[:plugins])
      folders = [Lux.root, Lux.fw_root].map { Pathname.new(_1).join('plugins', plugin_name.to_s) }
      root = folders.find(&:exist?)

      if root
        plugin = ::Lux::Plugin.load(root)
        result ||= plugin if plugin_name == names.first
        after = ::Lux::Plugin.normalize_names(Lux.config[:plugins])
        added = after.reject { |name| before.include?(name) }
        added.each { |name| queue << name unless seen[name] || queue.include?(name) }
      else
        Lux.shell.die [
          "Lux plugin '#{plugin_name}' not found",
          "searched: #{folders.map { _1.to_s }.join(', ')}"
        ]
      end
    end

    names.length == 1 ? result : nil
  end
end
