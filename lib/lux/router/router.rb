# Lux::Router - the root router (`Lux.router do ... end`, one instance per
# request) and the base class of every app router (`class MainRouter <
# FrontendRouter`, app/routers/main_router.rb). One class owns routing (`map`),
# actions, rendering, `before` hooks, `rescue_from` and `opt` / `allow`.

require 'erb'
require_relative '../context/lifecycle'
require_relative '../error/rescue_from'
require_relative '../policy/adapter'
require_relative './lib/routes'
require_relative './lib/routes_dumper'
require_relative './lib/params_dsl'
require_relative './lib/auto'
require_relative './lib/action'
require_relative './lib/callbacks'

module Lux
  class Router
    include ClassCallbacks
    include Lifecycle
    include Callbacks
    include Routes
    include ParamsDsl
    include Auto
    include Action
    include Lux::Policy::Authorize

    # Error handler, innermost router first (see #render_error). The block is
    # instance_exec'd on the router that was running, so it can `map` to the
    # router that renders the error page; ivars (incl. @error) pass along:
    #   rescue_from do |err|
    #     map 'promo#app_error'
    #   end
    extend Lux::RescueFrom

    DEFAULT_ERROR_TEMPLATE ||= ERB.new(Lux.fw_root.join('assets/router/error_page.html.erb').read)

    # per-instance framework state; @_ prefixed, so a mount never copies it
    IVARS ||= Struct.new 'LuxRouterIvars', :action, :layout, :render_cache, :only, :except, :resource
    RENDER_OPTS ||= Struct.new 'LuxRouterRenderOpts', :inline, :text, :plain, :html, :json, :javascript, :xml, :cache, :template, :layout, :render_to_string, :status, :ttl, :content_type

    # Layout name; views dir and helper follow it unless set. Inherited, so
    # `layout :x` in `Lux.router do` is the base of every router class.
    cattr :layout, class: true

    # view subfolder under template_root; `views :foo` overrides, else layout name
    cattr :views, class: true

    # helper module context; `helper :foo` overrides, else layout name
    cattr :helper, class: true

    # custom template root instead calcualted one
    cattr :template_root, default: './app/views', class: true

    # Root: part of the page pipeline, runs before CSRF and static files.
    # Router class: once when mounted, before its route or action.
    define_callback :before

    # right before a template renders
    define_callback :before_render

    class << self
      # Root router only - runs from Response#render, after the body is set and
      # before headers are written. Keyed by call site, like define_callback.
      def after &block
        raise ArgumentError, 'after runs only on the root router - declare it in Lux.router do ... end' unless self == Lux::Router

        (@class_callbacks_after ||= {})[caller[0].split(':in ').first] = block
      end

      # The routing block of this router. Calling it again replaces it.
      def route &block
        raise ArgumentError, 'route needs a block' unless block

        @route_block = block
      end

      # A router class inherits its parents' route, never the root's.
      def route_block
        return @route_block if self == Lux::Router

        klass = self
        while klass != Lux::Router
          return klass.instance_variable_get(:@route_block) if klass.instance_variable_defined?(:@route_block)
          klass = klass.superclass
        end
      end

      # Runs one action without routing (specs, consoles):
      #   MainRouter.action(:index)
      def action name, ivars: {}
        raise ArgumentError, 'Router action called with blank action name argument' if name.blank?

        router = new
        ivars.each { |k, v| router.instance_variable_set(k, v) }
        router.send :run_mounted, name.to_sym, Lux::Router
      end

      # create mock function, to enable template rendering
      # mock :index, :login
      def mock *args
        args.each do |el|
          define_method(el) { true }
        end
      end

      # Self-contained HTML error page (no template lookup): the default error
      # screen, and the 500 dump when the error handling itself fails. A
      # rescue_from target can render it to keep the framework chrome.
      def default_error_page status, error
        name      = ::Rack::Utils::HTTP_STATUS_CODES[status] || 'Error'
        message   = ERB::Util.html_escape(public_error_message(error, status))
        show_dev  = Lux.debug?
        backtrace = (show_dev && error.respond_to?(:backtrace) && error.backtrace) ?
                    error.backtrace.first(40).join("\n").gsub('<', '&lt;').gsub('>', '&gt;') : nil
        color     = status >= 500 ? '#dc2626' : status >= 400 ? '#d97706' : '#374151'

        DEFAULT_ERROR_TEMPLATE.result(binding)
      end

      # Messages of Lux::Error and policy errors are written for users; any
      # other exception text (SQL, paths, secrets) shows only in debug.
      def public_error_message error, status
        public_msg = error.is_a?(Lux::Error) || (defined?(Lux::Policy::Error) && error.is_a?(Lux::Policy::Error)) || Lux.debug?
        public_msg ? error.message.to_s : (::Rack::Utils::HTTP_STATUS_CODES[status] || 'Error')
      end

      # Returns a flat list of route Entries by replaying the route block
      # against a recorder. See lib/routes_dumper.rb for limitations.
      def dump_routes
        RoutesDumper.new(self).dump
      end
    end

    def initialize env = nil, opts = {}
      Lux::Context.new env, opts if env
      @_lux = IVARS.new
    end

    # Override in the app router class to skip CSRF for requests that carry no
    # ambient session (e.g. Basic-authed WebDAV verbs). Runs before `before`.
    def csrf_exempt?
      false
    end

    # main render called by Lux.call
    def render_base
      clear_dev_console

      if err = Lux.ctx.malformed_request
        raise Lux.error.bad_request Lux.debug?('400 Bad Request') { 'Malformed request: %s' % err.message }
      end

      # answered before reload, session, before hooks and auth, so probes stay cheap
      if Lux.ctx.request.path_info == '/healthcheck' && (Lux.ctx.request.get? || Lux.ctx.request.head?)
        return [200, { 'content-type' => 'text/plain' }, ['ok']]
      end

      raise Lux.error.forbidden('Bad host name') unless Lux.ctx.request.host.to_s.match?(/[a-z]/i)
      raise Lux.error.forbidden('Not allowed') if Lux.ctx.request.env['HTTP_SOAPACTION']

      # reload first, so before-filters run on the code just saved
      if Lux.reload? && Lux.runtime.web?
        Lux::Reloader.run
      end

      # Session handoff to another subdomain (nav.subdomain(..., session: true)),
      # both legs ahead of before-filters - they may demand the login it carries.
      # /_lux_/handoff mints the token at click time and redirects to the target;
      # the target takes ?_lux_st= and drops it from the URL, so history and
      # Referer never keep it.
      if Lux.ctx.request.get? && Lux.ctx.request.path_info == Lux::Context::Session::HANDOFF_PATH
        target = Lux.ctx.session.handoff(Lux.ctx.request.params['to']) or raise Lux.error.bad_request('bad handoff target')
        Lux.ctx.response.header 'cache-control', 'no-store'
        Lux.ctx.response.header 'referrer-policy', 'no-referrer'
        catch(:done) { Lux.ctx.response.redirect_to target }
        return Lux.ctx.response.render self
      end

      transfer = Lux::Context::Session::TRANSFER_PARAM
      if Lux.ctx.request.get? && (token = Lux.ctx.request.params[transfer])
        Lux.ctx.session.receive_transfer token
        Lux.ctx.response.header 'referrer-policy', 'no-referrer'
        catch(:done) { Lux.ctx.response.redirect_to Url.current.delete(transfer).relative, status: 303, silent: true }
        return Lux.ctx.response.render self
      end

      # /_lux_/dbsc/* - device-bound session endpoints, ahead of before-filters so
      # no app filter runs on the proof-exempt refresh. The browser posts them on
      # its own, without a CSRF token. See Lux::Context::Dbsc.
      if Lux.ctx.request.post? && Lux.ctx.request.path_info.start_with?(Lux::Context::Dbsc::PREFIX)
        Lux::Context::Dbsc.handle Lux.ctx
        return Lux.ctx.response.render self if Lux.ctx.response.body?
      end

      # CSRF: enforce for non-safe verbs that aren't Bearer-authenticated, before
      # app filters, so a `before` with side effects never runs on a forged POST.
      # Opt out per app with Lux.config.csrf = false, per path by overriding
      # #csrf_exempt? (e.g. Basic-authed, sessionless WebDAV). See Lux::Context#csrf.
      if Lux.config[:csrf] != false && !csrf_exempt? && Lux.ctx.csrf_required? && !Lux.ctx.csrf_valid?
        raise Lux.error.forbidden 'CSRF token missing or invalid'
      end

      # catch :done so an app-level before-filter can redirect/halt via
      # redirect_to (which throws :done); without it the throw escapes to the
      # rescue below and render_error downgrades the 302 to 500.
      catch(:done) { run_callback :before, Lux.ctx.nav.path }

      request_method = Lux.ctx.request.request_method

      Lux.log ''
      Lux.log { [request_method.colorize(:white), Lux.ctx.request.url].join(' ') }

      if Lux.ctx.request.post?
        Lux.log { filter_params(Lux.ctx.request.params.to_h).to_jsonp }
      end

      # Vanilla OPTIONS (no preflight) gets the canned allow+cache reply.
      # Preflight (OPTIONS + Access-Control-Request-Method) flows through so
      # `response.cors` in a before/action can answer it. See Lux::Response::Cors.
      # A before-hook that already set the body owns the response (e.g. WebDAV
      # OPTIONS needs its own DAV/allow headers) - do not overwrite it.
      if request_method == 'OPTIONS' && !Lux.ctx.request.env['HTTP_ACCESS_CONTROL_REQUEST_METHOD'] && !Lux.ctx.response.body?
        return [204, {
          'allow' => Lux.config[:request_options] || 'OPTIONS, GET, HEAD, POST',
          'cache-control' => 'max-age=604800',
        }, ['']]
      end

      # /_lux_/* - framework-served client assets (composed JS bundles).
      # Always GET; csrf is skipped because the response carries the current
      # token, not consumes one. See Lux::Browser::Mount.
      if request_method == 'GET' && Lux.ctx.request.path_info.start_with?(Lux::Browser::Mount::PREFIX)
        if result = Lux::Browser::Mount.handle(Lux.ctx)
          return result
        end
      end

      # a before-hook that already answered owns the path, even one under ./public
      if Lux.config.serve_static_files && !Lux.ctx.response.body?
        Lux::Response::File.deliver_from_current
      end

      resolve_routes unless Lux.ctx.response.body?

      raise Lux.error.not_found unless Lux.ctx.response.body?

      Lux.ctx.response.render self
    rescue StandardError => err
      render_error err
    end

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
    # Lux.router.new('/').render_page.body
    def render_page
      out  = @_response_render ||= render_base
      body = out[2].respond_to?(:join) ? out[2].join : out[2].to_a.join

      Page.new(out[0].to_i, out[1], body, Lux.ctx.session.hash.to_lux_hash)
    end

    private

    LAST_CONSOLE_CLEAR ||= [0.0]

    # Dev: wipe the terminal when a page is opened (full load or pjax), at most every
    # 2s, so the log shows the current page only. Assets, xhr and probes never clear.
    def clear_dev_console
      return unless Lux.env.dev? && !Lux.env.test? && Lux.runtime.web? && $stdout.tty?

      env = Lux.ctx.request.env
      return unless env['HTTP_SEC_FETCH_DEST'] == 'document' || env['HTTP_X_PJAX_LAYOUT']

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if now - LAST_CONSOLE_CLEAR[0] < 2

      LAST_CONSOLE_CLEAR[0] = now
      print "\e[H\e[2J\e[3J"
    end

    FILTERED_PARAMS ||= /pass|token|secret|card|cvv|otp|auth/i

    # Request params with credential-looking keys masked, for logging only.
    def filter_params value
      case value
      when ::Hash  then value.to_h { |k, v| [k, k.to_s.match?(FILTERED_PARAMS) ? '[FILTERED]' : filter_params(v)] }
      when ::Array then value.map { filter_params _1 }
      else value
      end
    end

    # Error sink. The innermost running router hands the error to its nearest
    # `rescue_from` (walking up to the root's). No handler, or a handler that
    # renders nothing, gets the default error screen. A handler that raises
    # gets the 500 dump.
    def render_error err
      # Lux::Error carries its status; a policy denial (`can.read!`) is an
      # expected 403, not a server error - same as Lux::Api::Response.client_error?
      policy = defined?(Lux::Policy::Error) && err.is_a?(Lux::Policy::Error)
      Lux.error.log err unless policy

      status =
        if err.is_a?(Lux::Error) then err.status
        elsif policy then 403
        else 500
        end
      Lux.ctx.response.status status

      app = Lux.ctx.var[:lux_router] || self
      app.instance_variable_set :@error, err
      app.instance_variable_set :@status, status
      Lux.ctx.var[:error_page] = true

      if (handler = app.class.rescue_handler_for(err)).is_a?(Proc)
        begin
          catch(:done) { app.instance_exec err, &handler }
        rescue StandardError => again
          return error_dump(again)
        end
      end

      default_error_screen status, err unless Lux.ctx.response.body?

      Lux.ctx.response.render
    end

    # No handler captured the error: JSON for JSON requests, else the framework page.
    def default_error_screen status, err
      if Lux.ctx.nav.format.to_s == 'json' || request.content_type.to_s.include?('json')
        Lux.ctx.response.body({ status: status, error: self.class.public_error_message(err, status) }.to_json, content_type: :json)
      else
        Lux.ctx.response.body self.class.default_error_page(status, err), content_type: :html
      end
    end

    # The error handler raised. Its response may be half written (set-once
    # body, a redirect's location), so answer with a bare tuple. Outside debug
    # the message stays hidden: it can carry SQL, paths or secrets.
    def error_dump err
      Lux.error.log err
      shown = Lux.debug? ? err : Lux.error(500)

      [500, { 'content-type' => 'text/html; charset=utf-8' }, [self.class.default_error_page(500, shown)]]
    end

    # The single `catch :done` for routing: the first dispatch that writes the
    # response body throws, unwinding the rest of the route in one step.
    def resolve_routes
      # the running router; mounts replace it with the innermost one, so
      # nav.load_models(ivars: true) and render_error reach the right instance
      Lux.ctx.var[:lux_router] = self

      catch :done do
        run_route
      end
    end
  end
end
