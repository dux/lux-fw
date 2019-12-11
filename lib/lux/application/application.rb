require_relative './lib/shared'
require_relative './lib/routes'

# frozen_string_literal: true

# Main application router

module Lux
  class Application
    include Routes
    include Shared

    define_callback :config    # pre boot app config
    define_callback :boot      # after rack app boot (web only)
    define_callback :info      # called by "lux config" cli
    define_callback :before    # before any page load
    define_callback :routes    # routes resolve
    define_callback :after     # after any page load
    define_callback :on_error  # on routing error

    boot do |rack_handler|
      # deafult host is required
      unless Lux.config.host.to_s.include?('http')
        raise 'Invalid "Lux.config.host"'
      end

      if Lux.config(:dump_errors)
        require 'binding_of_caller'
        require 'better_errors'

        rack_handler.use BetterErrors::Middleware
        BetterErrors.editor = :sublime
      end
    end

    def initialize current
      raise 'Config is not loaded (Lux.boot not called), cant render page' unless Lux.config.lux_config_loaded
      @_is_type_cache = {}
      @current = current
    end

    def render
      Lux.log { "\n#{request.request_method.white} #{request.url}" }

      if Lux.config(:auto_code_reload)
        Lux::Config.reload_modified_files
      end

      if Lux.config(:serve_static_files)
        catch(:done) { Lux::Response::File.deliver_asset(request) }
      end

      unless response.body?
        resolve_routes
      end

      response.render
    end

    private

    # Action to do if there is an application error.
    # You want to overload this in a production.
    def on_error error
      if Lux.dev? && error.is_a?(Lux::Error)
        Lux::Controller.action :on_error, error
      else
        raise error
      end
    end
  end
end
