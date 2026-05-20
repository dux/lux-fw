module Lux
  # get config hash pointer or die if key provided and not found
  def config
    @lux_config ||= Lux::Config.load.to_lux_hash
  end
  alias :secrets :config
end
