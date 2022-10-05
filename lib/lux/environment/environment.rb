module Lux
  class Environment
    ENVS = %w(development production test log live)

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
      ['production', 'log', 'live'].include?(@env_name)
    end
    alias :prod? :production?

    def test?
      $0.end_with?('/rspec') || @env_name == 'test'
    end

    def log?
      @env_name == 'log'
    end

    def rake?
      $0.end_with?('/rake')
    end

    def cli?
      !web?
    end

    def live?
      ENV['LUX_LIVE'] == 'true'
    end

    def web?
      if @env_web.nil?
        @env_web = ObjectSpace.each_object(Class).map(&:to_s).include?('#<Class:Rack::Server>')
      end

      @env_web
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
