module Lux
  # get config hash pointer or die if key provided and not found
  def config
    @lux_config ||= Lux::Config.load.to_hwia
  end
  alias :secrets :config
end
