# Lux.env     - environment name (dev/prod/test)
# Lux.mode    - behavior toggles (debug/reload)
# Lux.runtime - runtime kind (web/cli/rake)
#
# Env name resolution: ENV['LUX_ENV'] || ENV['RACK_ENV'] || 'development'.
# See Lux::Environment.resolve_name.
#
# Lux.env.to_s            # 'development'
# Lux.env == :dev         # true
# Lux.env == :development # true
# Lux.env.development?    # true
# Lux.env.dev?            # true

module Lux
  def env test = nil
    @env_base ||= Lux::Environment.new(Lux::Environment.resolve_name)

    test ? @env_base == test : @env_base
  end

  def mode
    @mode_base ||= Lux::Mode.new(Lux::Environment.resolve_name)
  end

  def runtime
    @runtime_base ||= Lux::Runtime.new
  end
end
