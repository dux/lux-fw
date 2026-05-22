module Lux
  # Shell/process execution + status output. See lib/lux/shell/.
  #
  #   Lux.shell                  -> Lux::Shell module (for .capture / .stream / .info / ...)
  #   Lux.shell(*argv, **opts)   -> shortcut for Lux::Shell.exec(...)
  def shell *args, **opts, &block
    return Lux::Shell if args.empty? && opts.empty? && !block
    Lux::Shell.exec(*args, **opts, &block)
  end
end
