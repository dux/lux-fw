# Lux.env.to_s            # 'development'
# Lux.env == :dev         # true
# Lux.env == :development # true
# Lux.env.development?    # true
# Lux.env.dev?            # true

module Lux
  def env test=nil
    @env_base ||= Lux::Environment.new ENV.fetch('RACK_ENV')

    test ? @env_base == test : @env_base
  end
end