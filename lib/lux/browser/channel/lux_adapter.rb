module Lux
  # Pub/sub channel by name. See lib/lux/browser/channel/.
  #
  #   Lux.channel(:notifications).push(message: 'Hello')
  def channel name
    Lux::Browser::Channel[name]
  end
end
