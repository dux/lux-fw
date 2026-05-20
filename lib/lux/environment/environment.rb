module Lux
  class Environment
    ENVS          ||= %w(development production test).freeze
    TEST_BINARIES ||= %w(rspec minitest m).freeze

    # Resolve the active env name. LUX_ENV wins over RACK_ENV; both empty
    # falls back to 'development' so quick-hack scripts work without setup.
    def self.resolve_name
      raw = ENV['LUX_ENV'].to_s
      raw = ENV['RACK_ENV'].to_s if raw.empty?
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
