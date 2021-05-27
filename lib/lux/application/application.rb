# Main application router

require_relative './lib/shared'
require_relative './lib/routes'

module Lux
  class Application
    include ClassCallbacks
    include Routes
    include Shared

    define_callback :config    # pre boot app config
    define_callback :info      # called by "lux config" cli
    define_callback :before    # before any page load
    define_callback :routes    # routes resolve
    define_callback :after     # after any page load

    def initialize env, opts={}
      Lux::Current.new env, opts if env
    end

    def render
      # screen log request header unless is static file
      unless nav.format
        if current.no_cache?
          error.clear_screen if Lux.env.dev?
        else
          puts $/ if Lux.config.log_to_stdout
        end

        Lux.log { [request.request_method.white, request.url].join(' ') }
      end

      if request.post?
        Lux.log { request.params.to_h.to_jsonp }
      end

      catch :done do
        begin
          if Lux.config.auto_code_reload
            Lux.config.on_code_reload.call
          end

          if Lux.config.serve_static_files
            Lux::Response::File.deliver_asset(request)
          end

          resolve_routes  unless response.body?
          error.not_found unless response.body?
        rescue => err
          rescue_from err
        end
      end

      response.render
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
      }.to_hwia
    end

    def mount opts
      target = opts.keys.first
      value  = opts.values.first

      return unless request.path.starts_with?(value)

      call target.call current.env
    end

    def rescue_from err
      Lux.log ' Lux.app#rescue_from not defined - fallback to default error capture'.red

      error.screen err
      error.render err
    end
  end
end
