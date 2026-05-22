module Lux
  # Code reloader for dev. See lib/lux/reloader/.
  #
  #   Lux.reloader.run        # reload files modified since last check
  def reloader
    Lux::Reloader
  end
end
