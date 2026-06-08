module Lux
  def init_env
    lux_env = ENV['LUX_ENV'].to_s
    lux_env = 'development' if lux_env.empty?
    # LUX_ENV is the source of truth; mirror into RACK_ENV so external
    # gems (puma, rack middleware) resolve the same environment.
    ENV['LUX_ENV'] = ENV['RACK_ENV'] = lux_env
    lux_env
  end

  # get config hash pointer or die if key provided and not found
  def config
    init_env
    @lux_config ||= Lux::Boot::Config.load.to_lux_hash
  end
  alias :secrets :config

  # Rails-style .env loader. Loads from most-specific to least-specific;
  # Dotenv.load is non-destructive, so earlier files win:
  #
  #   .env.<env>.local   - local overrides per environment (gitignored)
  #   .env.local         - local overrides (gitignored)
  #   .env.<env>         - per-environment defaults
  #   .env               - shared defaults
  #
  # Env name resolves from LUX_ENV, defaulting to 'development'.
  # Returns the list of files actually loaded.
  def dotenv
    require 'dotenv' unless defined?(Dotenv)

    env_name = init_env
    env_name = 'development'        if env_name.empty?

    files = [
      ".env.#{env_name}.local",
      '.env.local',
      ".env.#{env_name}",
      '.env'
    ].select { |f| File.exist?(f) }

    Dotenv.load(*files) if files.any?
    files
  end
end
