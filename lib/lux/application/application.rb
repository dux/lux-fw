# Main application router

require_relative '../current/lifecycle'
require_relative './lib/routes'
require_relative './lib/routes_dumper'

module Lux
  class Application
    include ClassCallbacks
    include Lifecycle
    include Routes

    # Returns a flat list of route Entries by replaying the routes block
    # against a recorder. See lib/routes_dumper.rb for limitations.
    def self.dump_routes
      RoutesDumper.new(self).dump
    end

    define_callback :before       # before any page load
    define_callback :routes       # routes resolve
    define_callback :after        # after any page load

    # Class-level wrappers for the routing DSL. Make `Lux.app do ... end` accept
    # `map`, `root`, `match`, `subdomain`, etc. at the top level without needing
    # a `routes do ... end` wrapper.
    #
    # Implementation: each call writes a proc directly into the routes-callback
    # ivar (`@class_callbacks_routes`) keyed by the user's call site, so calls
    # interleave correctly with explicit `routes do ... end` blocks in source
    # order. We bypass the public `routes` method because class-callbacks keys
    # by `caller[0]`, which would collapse to the same key for every call from
    # inside our wrapper.
    ROUTING_DSL ||= %i[map root match subdomain plugin_route plugin_routes favicon
                       get? head? post? delete? put? patch?]

    ROUTING_DSL.each do |name|
      define_singleton_method(name) do |*args, **kw, &block|
        @class_callbacks_routes ||= {}
        user_caller = caller[0]
        @class_callbacks_routes[user_caller] = proc do
          # Ruby 3 kwargs: `map admin: :admin` arrives as kw; pass it as a
          # positional Hash so instance `map` sees `route_object = {...}`.
          if kw.any?
            send(name, kw, &block)
          else
            send(name, *args, &block)
          end
        end
      end
    end

    # Catch-all for arbitrary instance-method calls at the top level of
    # `Lux.app do ... end`. Apps often define helper methods (`def general_rules`)
    # and call them inside `routes do ... end`. With `routes do` removed, those
    # calls happen at class-eval time — too early. Capture them here and replay
    # at request time so `general_rules; set_nav_id; map 'api'; ...` all work
    # as top-level statements without a `routes` wrapper.
    def self.method_missing(name, *args, **kw, &block)
      # Skip Ruby/Object internals so things like `inspect`, `class`, etc. work
      # normally during class definition.
      return super if name.to_s.start_with?('_')
      return super if Object.private_method_defined?(name) || Object.method_defined?(name)

      @class_callbacks_routes ||= {}
      user_caller = caller[0]
      @class_callbacks_routes[user_caller] = proc do
        if kw.any?
          send(name, *args, kw, &block)
        else
          send(name, *args, &block)
        end
      end
    end

    def self.respond_to_missing?(name, include_private = false)
      true
    end

    def initialize env, opts={}
      Lux::Current.new env, opts
    end

    # Sinatra-style shorthand for setting/getting the response body inside a
    # routes block. Forwards to Lux::Response#body, which handles all arg shapes
    # (data, data+opts, block transform, no-arg getter).
    def body *args, &blk
      args.empty? && !blk ? response.body : response.body(*args, &blk)
    end

    # main render called by Lux.call
    def render_base
      run_callback :before, lux.nav.path

      if Lux.mode.reload? && Lux.runtime.web?
        Lux::Reloader.run
      end

      request_method = lux.request.request_method

      Lux.log ''
      Lux.log { [request_method.colorize(:white), lux.request.url].join(' ') }

      if lux.request.post?
        Lux.log { lux.request.params.to_h.to_jsonp }
      end

      # Vanilla OPTIONS (no preflight) gets the canned allow+cache reply.
      # Preflight (OPTIONS + Access-Control-Request-Method) flows through so
      # `response.cors` in a before/action can answer it. See Lux::Response::Cors.
      if request_method == 'OPTIONS' && !lux.request.env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
        return [204, {
          'allow' => Lux.config[:request_options] || 'OPTIONS, GET, HEAD, POST',
          'cache-control' => 'max-age=604800',
        }, ['']]
      end

      # /_lux_/* - framework-served client assets (composed JS bundles).
      # Always GET; csrf is skipped because the response carries the current
      # token, not consumes one. See Lux::Browser::Mount.
      if request_method == 'GET' && lux.request.path_info.start_with?(Lux::Browser::Mount::PREFIX)
        if result = Lux::Browser::Mount.handle(lux)
          return result
        end
      end

      # CSRF: enforce for non-safe verbs that aren't Bearer-authenticated.
      # Opt-out per-app via Lux.config.csrf = false. See Lux::Current#csrf.
      if Lux.config[:csrf] != false && lux.csrf_required? && !lux.csrf_valid?
        raise Lux.error.forbidden 'CSRF token missing or invalid'
      end

      if Lux.config.serve_static_files
        Lux::Response::File.deliver_from_current
      end

      resolve_routes unless lux.response.body?

      raise Lux.error.not_found unless lux.response.body?

      lux.response.render self
    rescue StandardError => err
      render_error err
    end

    # Router-level catch-all error block, defined inside Lux.app do ... end.
    # The block is instance_exec'd on the Application instance, so it has access
    # to the routing DSL (`map`, `call`, etc.) — typically used to forward to a
    # controller that renders the error page:
    #   rescue_from do |err|
    #     LuxException.add err
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
      Lux.error.log err
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
      }.to_lux_hash
    end

    # internall call to resolve the routes. Per-action `route` annotations
    # are tried first (first match wins, source/load order), then the
    # `routes do` callbacks. Both halt via the :done catch when a handler
    # writes the response body.
    def resolve_routes
      # Expose the running Application instance so route-block helpers (e.g.
      # nav.ref_load_objects ivars: true) can export ivars that #call copies
      # into the controller via instance_variables_hash.
      lux.var[:lux_app] = self

      catch :done do
        resolve_action_routes
        run_callback :routes, lux.nav.path unless lux.response.body?
      end
    end

    # Walk Lux::Controller.action_routes and dispatch the first matching
    # entry. No-op when the registry is empty or nothing matches. Runs after
    # `before` filters have executed, so a before-filter that loads the
    # current user has already populated ivars before route resolution.
    def resolve_action_routes
      Lux::Controller.action_routes.each do |entry|
        next unless action_route_match?(entry[:path])
        call [entry[:controller], entry[:action]]
        return
      end
    end
  end
end
