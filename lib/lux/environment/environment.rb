module Lux
  class Environment
    ENVS         ||= %w(development production test)
    WEB_BINARIES ||= %w(puma rackup unicorn falcon thin iodine pitchfork).freeze
    WEB_CLASSES  ||= %w(Rack::Server Puma::Launcher Unicorn::HttpServer Falcon::Server Thin::Server).freeze
    TEST_BINARIES ||= %w(rspec minitest m).freeze

    def initialize env_name
      if env_name.empty?
        raise ArgumentError.new('RACK_ENV is not defined') # never default to "development", because it could be loaded as default in production
      elsif !ENVS.include?(env_name)
        raise ArgumentError.new('Unsupported environment: %s (supported are %s)' % [env_name, ENVS])
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
      @env_name == 'test' || TEST_BINARIES.include?(File.basename($PROGRAM_NAME))
    end

    def rake?
      File.basename($PROGRAM_NAME) == 'rake'
    end

    def live?
      return false if cli?
      ENV['LUX_LIVE'] == 'true'
    end

    def local?
      !live?
    end

    # True when running under a web server. Detection is layered:
    #   1. ENV['LUX_WEB'] override ('true'/'false')
    #   2. Known server binary in $PROGRAM_NAME
    #   3. Live instance of a known server class in ObjectSpace
    # Memoized after the first call.
    def web?
      return @env_web unless @env_web.nil?

      @env_web =
        case ENV['LUX_WEB']
          when 'true'  then true
          when 'false' then false
          else
            WEB_BINARIES.include?(File.basename($PROGRAM_NAME)) || web_instance_running?
        end
    end

    # runs in cli?
    def cli?
      !web?
    end

    # log level :info, log to screen and browser in dev
    # With a block, acts as a ternary helper (block evaluated only when log? is true):
    #   Lux.env.log?                       # => bool
    #   Lux.env.log?('short') { 'long' }   # => 'short' or 'long'
    def log? short = nil
      @log = ENV['LUX_ENV'].to_s.include?('l') if @log.nil?
      block_given? ? (@log ? yield : short) : @log
    end

    def reload?
      @reload = ENV['LUX_ENV'].to_s.include?('r') if @reload.nil?
      @reload
    end

    ###

    # Lux.env == :dev
    def == what
      return true if what.to_s == @env_name
      predicate = '%s?' % what
      respond_to?(predicate) ? send(predicate) : false
    end

    def to_s
      @env_name
    end

    private

    def web_instance_running?
      WEB_CLASSES.any? do |name|
        klass = name.split('::').inject(Object) do |scope, const|
          break nil unless scope.const_defined?(const, false)
          scope.const_get(const)
        end
        klass && ObjectSpace.each_object(klass).any?
      end
    end
  end
end
