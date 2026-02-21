module Lux
  class Environment
    ENVS ||= %w(development production test)

    def initialize env_name
      if env_name.empty?
        raise ArgumentError.new('RACK_ENV is not defined') # never default to "development", because it could be loaded as default in production
      elsif !ENVS.include?(env_name)
        raise ArgumentError.new('Unsupported environemt: %s (supported are %s)' % [env_name, ENVS])
      end

      @env_name = env_name
    end

    def development?
      @env_name != 'production'
    end
    alias :dev? development?

    def production?
      @env_name == 'production'
    end
    alias :prod? :production?

    def test?
      $0.end_with?('/rspec') || @env_name == 'test'
    end

    def rake?
      $0.end_with?('/rake')
    end

    def live?
      value = ENV['LUX_LIVE'] || Lux.die('ENV LUX_LIVE not defined')
      value == 'true'
    end

    def local?
      !live?
    end

    def web?
      if @env_web.nil?
        list = ObjectSpace.each_object(Class).map(&:to_s)
        @env_web = list.include?('#<Class:Rack::Server>') || list.include?('Puma::Launcher')
      end

      @env_web
    end

    # runs in cli?
    def cli?
      !web?
    end

    # log level :info, log to screen and browser in dev
    def log?
      @log = ENV['LUX_ENV'].include?('l') if @log.nil?
      @log
    end

    def reload?
      @reload = ENV['LUX_ENV'].include?('r') if @reload.nil?
      @reload
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
