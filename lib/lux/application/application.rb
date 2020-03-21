require_relative './lib/shared'
require_relative './lib/routes'

# frozen_string_literal: true

# Main application router

module Lux
  class Application
    include Routes
    include Shared
    include RescueFromError

    define_callback :config    # pre boot app config
    define_callback :boot      # after rack app boot (web only)
    define_callback :info      # called by "lux config" cli
    define_callback :before    # before any page load
    define_callback :routes    # routes resolve
    define_callback :after     # after any page load

    rescue_from :all do |error|
      out = "Server error (500)\n\n#{error.message} (#{error.class})"
      out += "\n\n---\n\nDevelopment info\n\n---\nYou need to redefine Lux.app { rescue_from(:all) {} }\n---\n\nBacktrace:\n#{error.backtrace.join($/)}" if Lux.env.dev?
      response.body = out
    end

    boot do |rack_handler|
      # deafult host is required
      unless Lux.config.host.to_s.include?('http')
        raise 'Invalid "Lux.config.host"'
      end

      if Lux.config(:dump_errors)
        # require 'binding_of_caller'
        require 'better_errors'

        rack_handler.use BetterErrors::Middleware
        BetterErrors.editor = :sublime
      end
    end

    def initialize env, opts={}
      Lux::Current.new env, opts if env
      raise 'Config is not loaded (Lux.boot not called), cant render page' unless Lux.config.lux_config_loaded
    end

    def render
      Lux.log { "\n#{request.request_method.white} #{request.url}" }

      Lux.log { JSON.pretty_generate(request.params.to_h) } if request.post?

      if Lux.config(:auto_code_reload)
        Lux.config(:on_code_reload)
      end

      catch :done do
        resolve_rescue_from do
          if Lux.config(:serve_static_files)
            Lux::Response::File.deliver_asset(request)
          end

          resolve_routes unless response.body?
          error.not_found unless response.body?
        end
      end

      @response_render ||= response.render
    end

    def info
      out  = @response_render ||= render
      body = out[2].join('')
      body = JSON.parse body if out[1]['content-type'].index('/json')

      {
        body:    body,
        time:    out[1]['x-lux-speed'],
        status:  out[0],
        session: current.session.hash,
        headers: out[1]
      }.to_ch
    end
  end
end
