module Lux
  class Environment
    ENVS           ||= %w(development production test).freeze
    TEST_BINARIES  ||= %w(rspec minitest m).freeze
    FIBER_BINARIES ||= %w(falcon).freeze

    # Resolve the active env name from LUX_ENV; empty falls back to
    # 'development' so quick-hack scripts work without setup.
    def self.resolve_name
      raw = ENV['LUX_ENV'].to_s
      raw.empty? ? 'development' : raw
    end

    def initialize env_name
      unless ENVS.include?(env_name)
        raise ArgumentError.new('Unsupported environment: %s (supported are %s)' % [env_name, ENVS])
      end

      @env_name = env_name
    end

    def development?
      @env_name != 'production'
    end
    alias :dev? :development?

    def production?
      @env_name == 'production'
    end
    alias :prod? :production?

    def test?
      @env_name == 'test' || TEST_BINARIES.include?(File.basename($PROGRAM_NAME))
    end

    # True when requests are served from fibers instead of threads (falcon or
    # any Fiber.scheduler based server). Scheduler presence is per-thread, so
    # plain background threads answer false - the binary check keeps the
    # answer stable process-wide under falcon. Not memoized on purpose.
    def fibers?
      !!Fiber.scheduler || FIBER_BINARIES.include?(File.basename($PROGRAM_NAME))
    end

    # Lux.env == :dev
    def == what
      return true if what.to_s == @env_name
      predicate = '%s?' % what
      respond_to?(predicate) ? send(predicate) : false
    end

    def to_s
      @env_name
    end
  end
end
