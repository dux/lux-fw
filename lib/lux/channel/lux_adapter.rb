module Lux
  # Pub/sub channel by name. See lib/lux/channel/.
  #
  #   Lux.channel(:notifications).push(message: 'Hello')
  def channel name
    Lux::Channel[name]
  end
end
