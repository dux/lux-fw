module Lux
  # first reads race on threaded servers; one thread loads, the rest wait
  CONFIG_LOCK ||= Mutex.new

  def init_env
    lux_env = Lux::Environment.resolve_name
    # LUX_ENV is the source of truth; mirror into RACK_ENV so external
    # gems (puma, rack middleware) resolve the same environment.
    ENV['LUX_ENV'] = ENV['RACK_ENV'] = lux_env
    lux_env
  end

  # get config hash pointer or die if key provided and not found
  #
  # Framework defaults are filled in on first load, not at boot, so
  # Lux.logger / Lux.log / Lux.defer work before Lux.boot!.
  def config
    # init_env writes ENV; do it once, not on every read (setenv racing a
    # getenv in a C extension on another thread can crash the process)
    @lux_config || CONFIG_LOCK.synchronize do
      @lux_config ||= begin
        init_env
        Lux::Boot.apply_defaults Lux::Boot::Config.load.to_lux_hash
      end
    end
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
  # Env name resolves from LUX_ENV (shell, else peeked from .env.local /
  # .env), defaulting to 'development'. Does not write LUX_ENV itself.
  # Returns the list of files actually loaded.
  def dotenv
    require 'dotenv' unless defined?(Dotenv)

    env_name = ENV['LUX_ENV'].to_s
    if env_name.empty?
      # LUX_ENV may itself live in an env-agnostic file; Dotenv.load never
      # overwrites ENV, so peek before choosing the env-specific files
      env_name = %w[.env.local .env].filter_map { File.exist?(_1) && Dotenv.parse(_1)['LUX_ENV'] }.find { !_1.to_s.empty? }.to_s
    end
    env_name = 'development' if env_name.empty?

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
