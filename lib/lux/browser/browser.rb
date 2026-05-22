require 'erb'

module Lux
  # Lux::Browser - server-side composer for the window.Lux client surface.
  #
  # Subsystems register their JS modules; Lux::Browser.client(:sse, :api)
  # returns a single bundle that's served at /lux/*.js with per-request
  # state (csrf, locale, host) interpolated via ERB.
  #
  #   Lux::Browser.register :sse, file: 'assets/lux/sse.js'
  #   Lux::Browser.client                # all modules, core first
  #   Lux::Browser.client(:sse)          # core + sse only
  #   Lux::Browser.modules               # [:core, :sse, ...]
  module Browser
    extend self

    @modules ||= {}

    # Register a JS module file. Paths starting with '/' are absolute; others
    # resolve relative to Lux.fw_root.
    def register name, file:
      @modules[name.to_sym] = file.to_s
    end

    def modules
      @modules.keys
    end

    def registered? name
      @modules.key?(name.to_sym)
    end

    # Returns the composed bundle as a string. :core is always first.
    #
    #   client                     -> every registered module (core + rest)
    #   client(:all)               -> same as no-arg
    #   client(:sse)               -> core + sse
    #   client(:sse, :api)         -> core + sse + api
    def client *names
      selected =
        if names.empty? || names == [:all]
          @modules.keys
        else
          names.map(&:to_sym)
        end

      # core first, then requested in given order, deduped
      ordered = ([:core] + selected).uniq

      ordered.map { |n|
        path = @modules[n] or raise ArgumentError, "Lux::Browser: unknown module #{n.inspect} (registered: #{@modules.keys})"
        render File.expand_path(path, Lux.fw_root.to_s)
      }.join("\n")
    end

    private

    def render path
      ERB.new(File.read(path), trim_mode: '-').result(binding)
    end
  end
end

# Self-register the core module.
Lux::Browser.register :core, file: 'assets/lux/core.js'
