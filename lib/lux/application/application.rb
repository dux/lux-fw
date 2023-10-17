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
        Lux.log ''
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

      catch :done do
        if Lux.config.serve_static_files
          Lux::Response::File.deliver_asset(request)
        end

        resolve_routes unless response.body?
      end

      catch :done do
        error.not_found unless response.body?
      end

      response.render
    rescue => err
      Lux.current.error ||= err
      Lux.error.screen Lux.current.error
      render_error
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

    def render_error
      err = Lux.current.error ||= $!
      Lux.info "Unhandled error (definef render_error in routes): [#{err.class}] #{err.message}"
      Lux.error.log err
      raise err
    end
  end
end
