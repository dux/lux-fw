module Lux
  # get config hash pointer or die if key provided and not found
  def config
    @lux_config ||= Lux::Config.load.to_lux_hash
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
  # Env name resolves from LUX_ENV, then RACK_ENV, then 'development'.
  # Returns the list of files actually loaded.
  def dotenv
    require 'dotenv' unless defined?(Dotenv)

    env_name = ENV['LUX_ENV'].to_s
    env_name = ENV['RACK_ENV'].to_s if env_name.empty?
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
