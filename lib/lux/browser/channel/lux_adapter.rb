module Lux
  # Pub/sub channel by name. See lib/lux/browser/channel/.
  #
  #   Lux.channel(user).push(message: 'Hello')   # -> "user:<ref>"
  def channel name
    Lux::Browser::Channel[name]
  end
end
