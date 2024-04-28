# Main application router

require_relative './lib/shared'
require_relative './lib/routes'

module Lux
  class Application
    include ClassCallbacks
    include Routes
    include Shared

    define_callback :before    # before any page load
    define_callback :routes    # routes resolve
    define_callback :after     # after any page load

    def initialize env, opts={}
      Lux::Current.new env, opts
    end

    # main render called by Lux.call
    def render_base
      if Lux.env.reload_code? && Lux.env.web?
        Lux.config.on_reload_code.call
      end

      request_method = request.request_method

      Lux.log ''
      Lux.log { [request_method.white, request.url].join(' ') }

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
          Lux::Response::File.deliver_from_current
        end

        resolve_routes unless response.body?
      end

      catch :done do
        Lux.error.not_found unless response.body?
      end

      response.render
    rescue => error
      if respond_to?(:rescue_from)
        catch :done do
          rescue_from error
        end

        response.render
      else
        raise error
      end
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
      Lux.info "Unhandled error (define render_error in routes): [#{err.class}] #{err.message}"
      Lux.error.log err
      raise err
    end

    def favicon path
      cpath = request.path.downcase

      if !response.body? && cpath.start_with?('/favicon') || cpath.start_with?('/apple-touch-icon')
        response.max_age = 600 if response.max_age.to_i == 0

        icon = Lux.root.join(path)
        if icon.exist?
          response.send_file(icon, inline: true)
        else
          Lux.error.not_found '%s not found' % path
        end
      end
    end

    # internall call to resolve the routes
    def resolve_routes
      @magic = MagicRoutes.new self

      run_callback :before, nav.path
      run_callback :routes, nav.path

      unless response.body?
        Lux.error.not_found 'Document not found'
      end

      run_callback :after, nav.path
    end
  end
end
