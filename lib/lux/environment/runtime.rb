# Runtime kind: web server vs CLI vs rake task.
# Pure derivation from $PROGRAM_NAME / ObjectSpace, with LUX_WEB override.
# No env coupling.
#
#   Lux.runtime.web?   # running under puma/rackup/falcon/...
#   Lux.runtime.cli?   # !web?
#   Lux.runtime.rake?  # invoked via the rake binary

module Lux
  class Runtime
    WEB_BINARIES ||= %w(puma rackup unicorn falcon thin iodine pitchfork).freeze
    WEB_CLASSES  ||= %w(Rack::Server Puma::Launcher Unicorn::HttpServer Falcon::Server Thin::Server).freeze

    # Memoized after first call. Detection layers:
    #   1. ENV['LUX_WEB'] override
    #   2. known server binary in $PROGRAM_NAME
    #   3. live instance of a known server class in ObjectSpace
    def web?
      return @web unless @web.nil?

      @web =
        case ENV['LUX_WEB']
          when 'true'  then true
          when 'false' then false
          else
            WEB_BINARIES.include?(File.basename($PROGRAM_NAME)) || web_instance_running?
        end
    end

    def cli?
      !web?
    end

    def rake?
      File.basename($PROGRAM_NAME) == 'rake'
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
