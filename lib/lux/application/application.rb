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

    def render_base
      if Lux.config.code_reload && Lux.env.web?
        Lux.config.on_code_reload.call
      end

      request_method = request.request_method

      # screen log request header unless is static file
      unless nav.format
        if current.no_cache?
          error.clear_screen if Lux.env.dev?
        else
          Lux.log ''
        end

        Lux.log { [request_method.white, request.url].join(' ') }
      end

      if request.post?
        Lux.log { request.params.to_h.to_jsonp }
      end

      if request_method == 'OPTIONS'
        return [204, {
          'allow' => Lux.config[:request_options] || 'OPTIONS, GET, HEAD, POST',
          'cache-control' => 'max-age=604800',
        }, ['']]
      end

      if Lux.config.serve_static_files
        Lux::Response::File.deliver_asset(request)
      end

      catch :done do
        resolve_routes unless response.body?
      end

      catch :done do
        error.not_found unless response.body?
      end

      response.render
    rescue => err
      error.log err

      catch(:done) do
        render_error(err)
      end

      response.render
    end

    # to get root page body
    # Lux.app.new('/').render.body
    def render
      out  = @response_render ||= render_base
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

      return unless request.path.to_s.starts_with?(value)

      call target.call current.env
    end

    def render_error err
      Lux.error.screen err
      response.body "Server error: %s (%s)\n\nCheck log for details" % [err.message, err.class], status: 500
      response.render
    end
  end
end
