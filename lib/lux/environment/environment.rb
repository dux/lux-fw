module Lux
  class Environment
    ENVS ||= %w(development production test)

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

    def cli?
      !web?
    end

    def no_cache?
      @no_cache = ENV['LUX_ENV'].include?('c') if @no_cache.nil?
      @no_cache
    end

    def show_errors?
      @show_errors = ENV['LUX_ENV'].include?('e') if @show_errors.nil?
      @show_errors
    end

    def reload_code?
      @reload_code = ENV['LUX_ENV'].include?('c') if @reload_code.nil?
      @reload_code
    end

    def screen_log?
      @screen_log = ENV['LUX_ENV'].include?('l') if @screen_log.nil?
      @screen_log
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
