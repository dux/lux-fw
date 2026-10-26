module Lux
  class Browser
    # Handles requests under /_lux_/*. Called from Router#render_base
    # before route resolution. The /_lux_/ namespace is reserved for the
    # framework - apps must not register routes under it.
    #
    #   /_lux_/client.js             -> Lux::Browser.client_js (all modules)
    #   /_lux_/client.js?modules=sse,api -> Lux::Browser.client_js(:sse, :api)
    #   /_lux_/<module>.js           -> Lux::Browser.client_js(:<module>)  (just that one + core)
    #   /_lux_/stream                -> SSE stream for the session's channels
    #
    # POST /_lux_/dbsc/* belongs to Lux::Context::Dbsc and GET /_lux_/handoff
    # to Lux::Context::Session, not to this module.
    module Mount
      PREFIX       ||= '/_lux_/'.freeze
      JS_PATH      ||= %r{\A/_lux_/(?<name>[a-z0-9_]+)\.js\z}

      # Returns a Rack triplet, or nil if the path doesn't match anything we serve.
      def self.handle ctx
        path = ctx.request.path_info
        return nil unless path.start_with?(PREFIX)

        if path == '/_lux_/client.js'
          mods = ctx.request.params['modules'].to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_sym)
          return [404, headers_html, ['unknown lux module']] if mods.any? { _1 != :all && !Lux::Browser.registered?(_1) }
          return serve(ctx, Lux::Browser.client_js(*mods))
        end

        return stream(ctx) if path == '/_lux_/stream'

        if m = JS_PATH.match(path)
          name = m[:name].to_sym
          return [404, headers_html, ['unknown lux module']] unless Lux::Browser.registered?(name)
          return serve(ctx, Lux::Browser.client_js(name))
        end

        nil
      end

      # SSE endpoint - one stream per session. Takes no parameters: what a
      # connection receives comes from Lux::Browser::Channel.session_channels,
      # so a client cannot ask for someone else's channel and there is nothing
      # to authorize. Routing within the stream is the client's job - every
      # frame carries its channel name.
      def self.stream ctx
        return [501, headers_html, ['no session_channels resolver']] unless Lux::Browser::Channel.session_channels

        channels = Lux::Browser::Channel.channels_for(ctx).select { Lux::Browser::Channel::NAME.match?(_1) }

        return [403, headers_html, ['no channels for this session']] if channels.empty?

        [200, headers_sse, Lux::Response::Sse::StreamBody.new(channels)]
      end

      # Bundles change only on deploy, so browsers and CDNs may keep them; the
      # deploy id is the validator. Dev (Lux.reload?) never caches.
      JS_MAX_AGE ||= 3600

      def self.serve ctx, body
        return [200, headers_js.merge('cache-control' => 'no-cache, no-store'), [body]] if Lux.reload?

        etag    = %["#{Lux::DEPLOY_ID}"]
        headers = headers_js.merge('cache-control' => "public, max-age=#{JS_MAX_AGE}", 'etag' => etag)
        return [304, headers.except('content-type'), []] if ctx.request.env['HTTP_IF_NONE_MATCH'] == etag

        [200, headers, [body]]
      end

      def self.headers_js
        { 'content-type' => 'application/javascript; charset=utf-8' }
      end

      def self.headers_html
        { 'content-type' => 'text/plain; charset=utf-8' }
      end

      def self.headers_sse
        {
          'content-type'      => 'text/event-stream; charset=utf-8',
          'cache-control'     => 'no-cache, no-transform',
          'connection'        => 'keep-alive',
          'x-accel-buffering' => 'no',
        }
      end

      private_class_method :stream, :serve, :headers_js, :headers_html, :headers_sse
    end
  end
end
