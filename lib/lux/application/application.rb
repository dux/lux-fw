# Main application router

require_relative '../current/lifecycle'
require_relative '../error/rescue_from'
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
    #
    # The key also carries how many times that site ran in the current
    # `Lux.app` pass, so `%w[a b].each { map _1, ... }` registers both, while a
    # reload re-running the same block overwrites them instead of appending.
    ROUTING_DSL ||= %i[map call root subdomain plugin_route plugin_routes localized
                       get? head? post? delete? put? patch?]

    ROUTING_DSL.each do |name|
      define_singleton_method(name) do |*args, **kw, &block|
        @class_callbacks_routes ||= {}
        site = caller[0]
        seen = @dsl_seen ? (@dsl_seen[site] = @dsl_seen.fetch(site, -1) + 1) : 0
        @class_callbacks_routes["#{site}##{seen}"] = proc do
          # Ruby 3 kwargs: none of the instance DSL methods take keywords, so a
          # trailing hash arrives here as `kw`. Append it as a positional arg -
          # that covers both `map admin: :admin` (route_object) and
          # `map 'users', 'admin/users', foo: :bar` (opts), which would lose its
          # positional args if kw replaced them.
          full_args = kw.any? ? args + [kw] : args
          send(name, *full_args, &block)
        end
      end
    end

    # One `Lux.app { }` evaluation; see ROUTING_DSL for why call sites are counted.
    def self.dsl_pass &block
      @dsl_seen = {}
      class_eval(&block)
    ensure
      @dsl_seen = nil
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
      if err = lux.malformed_request
        raise Lux.error.bad_request Lux.debug?('400 Bad Request') { 'Malformed request: %s' % err.message }
      end

      # reload first, so before-filters run on the code just saved
      if Lux.reload? && Lux.runtime.web?
        Lux::Reloader.run
      end

      # Session handoff to another subdomain (nav.subdomain(..., session: true)),
      # both legs ahead of before-filters - they may demand the login it carries.
      # /_lux_/handoff mints the token at click time and redirects to the target;
      # the target takes ?_lux_st= and drops it from the URL, so history and
      # Referer never keep it.
      if lux.request.get? && lux.request.path_info == Lux::Current::Session::HANDOFF_PATH
        target = lux.session.handoff(lux.request.params['to']) or raise Lux.error.bad_request('bad handoff target')
        lux.response.header 'cache-control', 'no-store'
        lux.response.header 'referrer-policy', 'no-referrer'
        catch(:done) { lux.response.redirect_to target }
        return lux.response.render self
      end

      transfer = Lux::Current::Session::TRANSFER_PARAM
      if lux.request.get? && (token = lux.request.params[transfer])
        lux.session.receive_transfer token
        lux.response.header 'referrer-policy', 'no-referrer'
        catch(:done) { lux.response.redirect_to Url.current.delete(transfer).relative, status: 303, silent: true }
        return lux.response.render self
      end

      # catch :done so an app-level before-filter can redirect/halt via
      # redirect_to (which throws :done); without it the throw escapes to the
      # rescue below and render_error downgrades the 302 to 500.
      catch(:done) { run_callback :before, lux.nav.path }

      request_method = lux.request.request_method

      Lux.log ''
      Lux.log { [request_method.colorize(:white), lux.request.url].join(' ') }

      if lux.request.post?
        Lux.log { filter_params(lux.request.params.to_h).to_jsonp }
      end

      # Vanilla OPTIONS (no preflight) gets the canned allow+cache reply.
      # Preflight (OPTIONS + Access-Control-Request-Method) flows through so
      # `response.cors` in a before/action can answer it. See Lux::Response::Cors.
      # A before-hook that already set the body owns the response (e.g. WebDAV
      # OPTIONS needs its own DAV/allow headers) - do not overwrite it.
      if request_method == 'OPTIONS' && !lux.request.env['HTTP_ACCESS_CONTROL_REQUEST_METHOD'] && !lux.response.body?
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

      # /_lux_/dbsc/* - device-bound session endpoints. The browser posts them on
      # its own, without a CSRF token. See Lux::Current::Dbsc.
      if request_method == 'POST' && !lux.response.body? && lux.request.path_info.start_with?(Lux::Current::Dbsc::PREFIX)
        Lux::Current::Dbsc.handle lux
      end

      # CSRF: enforce for non-safe verbs that aren't Bearer-authenticated.
      # Opt-out per-app via Lux.config.csrf = false. See Lux::Current#csrf.
      # Responses already produced by a before-hook are exempt (e.g. WebDAV
      # PROPFIND is Basic-authed and sessionless - not CSRF-vulnerable).
      if Lux.config[:csrf] != false && !lux.response.body? && lux.csrf_required? && !lux.csrf_valid?
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

    # Router-level error handler (Lux::RescueFrom), defined inside Lux.app do ... end.
    # The block is instance_exec'd on the Application instance, so it has access
    # to the routing DSL (`map`, `call`, etc.) - typically used to forward to a
    # controller that renders the error page:
    #   rescue_from do |err|
    #     LuxException.add err
    #     call 'promo#app_error'   # ivars (incl. @error) auto-pass
    #   end
    extend Lux::RescueFrom

    # Finished response of a server-side render (Lux.render.get/post/...).
    Page ||= Struct.new(:status, :headers, :body, :session) do
      def json
        @json ||= JSON.parse(body).then { _1.is_a?(::Hash) ? _1.to_lux_hash : _1 }
      end

      def redirect_to = headers['location']
      def ok?         = status.between?(200, 299)
      def time        = headers['x-lux-speed']
    end

    # full page render
    # Lux.app.new('/').render_page.body
    def render_page
      out  = @response_render ||= render_base
      body = out[2].respond_to?(:join) ? out[2].join : out[2].to_a.join

      Page.new(out[0].to_i, out[1], body, lux.session.hash.to_lux_hash)
    end

    private

    FILTERED_PARAMS ||= /pass|token|secret|card|cvv|otp|auth/i

    # Request params with credential-looking keys masked, for logging only.
    def filter_params value
      case value
      when ::Hash  then value.to_h { |k, v| [k, k.to_s.match?(FILTERED_PARAMS) ? '[FILTERED]' : filter_params(v)] }
      when ::Array then value.map { filter_params _1 }
      else value
      end
    end

    # Error sink. Resolution order:
    #   1. A Lux.app rescue_from handler matches the error → run it (typically
    #      dispatches to a controller via `call 'foo#error'`)
    #   2. Active controller defines :error → use it directly
    #   3. Framework default → Lux::Error.render (server-dump style)
    # If anything in 1 or 2 raises, Lux.call's outer rescue returns a low-level Rack tuple.
    def render_error err
      # a policy denial (`can.read!`) is an expected 403, not a server error -
      # same as Lux::Api::Response.client_error?
      if defined?(Lux::Policy::Error) && err.is_a?(Lux::Policy::Error)
        lux.response.status 403 unless lux.response.status.to_i >= 400
      else
        Lux.error.log err
      end

      # Lux.error helpers set lux.response.status before raising; honour that.
      # Anything else (raw StandardError) defaults to 500.
      status = lux.response.status.to_i
      status = 500 unless status >= 400
      lux.response.status status

      @error  = err
      @status = status
      lux.var[:error_page] = true

      klass = lux.var[:active_controller]

      # catch :done so the rescue/render path can use any router primitive
      # (`call`, `map`) without the throw escaping back up to Lux.call's outer rescue.
      catch :done do
        if handler = self.class.rescue_handler_for(err)
          instance_exec err, &handler
        elsif klass && klass.method_defined?(:error)
          # Dispatch :error in the same scope the failed action ran in. @error/
          # @status are set above and the router exported @realm/@object/... onto
          # this instance (load_models ivars:true), so passing the full ivar set
          # mirrors the normal `call` dispatch and the rescue_from -> map branch.
          klass.action :error, ivars: instance_variables_hash
        else
          Lux::Error.render err
        end
      end

      lux.response.render
    end

    # internall call to resolve the routes. Runs the `routes` callbacks in
    # source order. This is the single `catch :done` for routing: the first
    # dispatch that writes the response body throws, unwinding the rest of the
    # route statements (and any remaining `routes` callbacks) in one step.
    def resolve_routes
      # Expose the running Application instance so route-block helpers (e.g.
      # nav.load_models ivars: true) can export ivars that #call copies
      # into the controller via instance_variables_hash.
      lux.var[:lux_app] = self

      catch :done do
        run_callback :routes, lux.nav.path
      end
    end
  end
end
