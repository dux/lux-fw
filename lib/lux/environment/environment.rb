module Lux
  class Environment
    ENVS = %w(development production test log)

    def initialize env_name
      unless ENVS.include?(env_name)
        raise ArgumentError.new('Unsupported environemt: %s (supported are %s)' % [env_name, ENVS])
      end

      @env_name = env_name
    end

    def development?
      @env_name != 'production'
    end
    alias :dev? development?

    def production?
      ['production', 'log'].include?(@env_name)
    end
    alias :prod? :production?

    def test?
      @env_name == 'test'
    end

    def log?
      @env_name == 'log'
    end

    def rake?
      $0.end_with?('/rake')
    end

    def cli?
      !$rack_handler
    end

    ###

    # Lux.env == :dev
    def == what
      return true if what.to_s == @env_name
      send '%s?' % what
    end

    def to_s
      production? ? 'production' : 'development'
    end
  end
end
