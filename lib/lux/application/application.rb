# Main application router

require_relative '../lifecycle'
require_relative './lib/routes'

module Lux
  class Application
    include ClassCallbacks
    include Lifecycle
    include Routes

    define_callback :before       # before any page load
    define_callback :routes       # routes resolve
    define_callback :after        # after any page load

    def initialize env, opts={}
      Lux::Current.new env, opts
    end

    # main render called by Lux.call
    def render_base
      run_callback :before, lux.nav.path

      if Lux.env.reload? && Lux.env.web?
        Lux::Reloader.run
      end

      request_method = lux.request.request_method

      Lux.log ''
      Lux.log { [request_method.colorize(:white), lux.request.url].join(' ') }

      if lux.request.post?
        Lux.log { lux.request.params.to_h.to_jsonp }
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

      resolve_routes unless lux.response.body?

      Lux.error.not_found unless lux.response.body?

      lux.response.render self
    rescue StandardError => err
      render_error err
    end

    # Router-level catch-all error block, defined inside Lux.app do ... end.
    # The block is instance_exec'd on the Application instance, so it has access
    # to the routing DSL (`map`, `call`, etc.) — typically used to forward to a
    # controller that renders the error page:
    #   rescue_from do |err|
    #     ExceptionDb.add err
    #     map 'promo#app_error'   # router map; ivars (incl. @error) auto-pass
    #   end
    def self.rescue_from &block
      define_method(:app_rescue_from) { |error| instance_exec(error, &block) }
    end

    # Default fallback when no controller-level :error and no Lux.app rescue_from
    # are defined. Renders the Lux-branded error page.
    def rescue_from err
      Lux::Error.render err
    end

    # Error sink. Resolution order:
    #   1. Lux.app rescue_from is registered → run it (always wins when present;
    #      typically dispatches to a controller via `map 'foo#error'`)
    #   2. Active controller defines :error → use it directly
    #   3. Framework default → Lux::Error.render (server-dump style)
    # If anything in 1 or 2 raises, Lux.call's outer rescue returns a low-level Rack tuple.
    def render_error err
      Lux.logger.error Lux::Error.format(err, message: true, gems: false)
      # Lux.error helpers set lux.response.status before raising; honour that.
      # Anything else (raw StandardError) defaults to 500.
      status = lux.response.status.to_i
      status = 500 unless status >= 400
      lux.response.status status

      @error  = err
      @status = status

      klass = lux.var[:active_controller]

      # catch :done so the rescue/render path can use any router primitive
      # (`call`, `map`) without the throw escaping back up to Lux.call's outer rescue.
      catch :done do
        if respond_to?(:app_rescue_from)
          app_rescue_from err
        elsif klass && klass.method_defined?(:error)
          klass.action :error, ivars: { '@error' => err, '@status' => status }
        else
          rescue_from err
        end
      end

      lux.response.render
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
        session: lux.session.hash,
        headers: out[1]
      }.to_hwia
    end

    def mount opts
      target = opts.keys.first
      value  = opts.values.first

      return unless lux.request.path.to_s.start_with?(value)

      lux.response.rack target, mount_at: value
    end

    def favicon path
      cpath = lux.request.path.downcase

      if !lux.response.body? && (cpath.start_with?('/favicon') || cpath.start_with?('/apple-touch-icon'))
        lux.response.max_age = 600 if lux.response.max_age.to_i == 0

        icon = Lux.root.join(path)
        if icon.exist?
          lux.response.send_file(icon, inline: true)
        else
          Lux.error.not_found '%s not found' % path
        end
      end
    end

    # internall call to resolve the routes
    def resolve_routes
      catch :done do
        run_callback :routes, lux.nav.path
      end
    end
  end
end
