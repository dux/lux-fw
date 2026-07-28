# Lux.env      - environment name (dev/prod/test)
# Lux.debug?   - behavior toggles, see environment/flags.rb
# Lux.reload?
# Lux.silent
# Lux.runtime  - runtime kind (web/cli/rake)
#
# Env name resolution: ENV['LUX_ENV'] || 'development'.
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

  def runtime
    @runtime_base ||= Lux::Runtime.new
  end

  # The flags object. Call sites use the flat delegators below - this is for
  # the boot banner (iterates FLAGS by name) and for Lux.flags.reload_env!.
  def flags
    @flags_base ||= Lux::Environment::Flags.new(Lux::Environment.resolve_name)
  end

  def debug? short = nil, &block
    flags.debug? short, &block
  end

  def reload? short = nil, &block
    flags.reload? short, &block
  end

  def debug= value
    flags.debug = value
  end

  def reload= value
    flags.reload = value
  end

  def silent value = nil, &block
    flags.silent value, &block
  end
end
