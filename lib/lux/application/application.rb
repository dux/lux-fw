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
      run_callback :before, nav.path

      if Lux.env.reload? && Lux.env.web?
        Lux.config.on_reload_code.call
      end

      request_method = request.request_method

      Lux.log ''
      Lux.log { [request_method.colorize(:white), request.url].join(' ') }

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
        Lux::Response::File.deliver_from_current
      end

      resolve_routes unless response.body?

      Lux.error.not_found unless response.body?

      run_callback :after, nav.path
      response.render
    rescue StandardError => err
      Lux.logger.error Lux::Error.format(err, message: true, gems: false)
      respond_to?(:app_rescue_from) ? app_rescue_from(err) : rescue_from(err)
      response.render
    end

    # override in Lux.app do ... end block:
    #   rescue_from do |error|
    #     render '/main/error_500', status: 500
    #   end
    def self.rescue_from &block
      define_method(:app_rescue_from) { |error| instance_exec(error, &block) }
    end

    # default error handler — renders Lux-branded error page
    def rescue_from error
      Lux::Error.render error
    end

    # render text: 'ok'
    # render json: { error: 'not found' }, status: 404
    # render html: '<h1>Error</h1>', status: 500
    def render opts = {}
      if opts.keys.length == 0
        # no args → full page render proxy
        render_page
      else
        types = [:text, :html, :json, :javascript, :xml]
        for type in types
          if value = opts[type]
            response.status opts[:status] if opts[:status]
            response.body value, content_type: type
            return
          end
        end

        raise ArgumentError.new("Router render supports only #{types.keys.join(', ')}")
      end
    end

    # full page render — returns response hash
    # Lux.app.new('/').render_page.body
    def render_page
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

      return unless request.path.to_s.start_with?(value)

      response.rack target
    end

    def favicon path
      cpath = request.path.downcase

      if !response.body? && (cpath.start_with?('/favicon') || cpath.start_with?('/apple-touch-icon'))
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
      catch :done do
        run_callback :routes, nav.path
      end
    end
  end
end
