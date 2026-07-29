module Lux
  class Browser
    # Handles requests under /_lux_/*. Called from Application#render_base
    # before route resolution. The /_lux_/ namespace is reserved for the
    # framework - apps must not register routes under it.
    #
    #   /_lux_/client.js             -> Lux::Browser.client_js (all modules)
    #   /_lux_/client.js?modules=sse,api -> Lux::Browser.client_js(:sse, :api)
    #   /_lux_/<module>.js           -> Lux::Browser.client_js(:<module>)  (just that one + core)
    #   /_lux_/stream                -> SSE stream for the session's channels
    module Mount
      PREFIX       ||= '/_lux_/'.freeze
      JS_PATH      ||= %r{\A/_lux_/(?<name>[a-z0-9_]+)\.js\z}
      CHANNEL_NAME ||= /\A[a-zA-Z0-9_:.\-]{1,128}\z/

      # Returns a Rack triplet, or nil if the path doesn't match anything we serve.
      def self.handle lux
        path = lux.request.path_info
        return nil unless path.start_with?(PREFIX)

        if path == '/_lux_/client.js'
          mods = lux.request.params['modules'].to_s.split(',').map(&:to_sym).reject(&:empty?)
          return serve(Lux::Browser.client_js(*mods))
        end

        return stream(lux) if path == '/_lux_/stream'

        if m = JS_PATH.match(path)
          name = m[:name].to_sym
          return [404, headers_html, ['unknown lux module']] unless Lux::Browser.registered?(name)
          return serve(Lux::Browser.client_js(name))
        end

        nil
      end

      # SSE endpoint - one stream per session. Takes no parameters: what a
      # connection receives comes from Lux::Browser::Channel.session_channels,
      # so a client cannot ask for someone else's channel and there is nothing
      # to authorize. Routing within the stream is the client's job - every
      # frame carries its channel name.
      def self.stream lux
        return [501, headers_html, ['no session_channels resolver']] unless Lux::Browser::Channel.session_channels

        channels = Lux::Browser::Channel.channels_for(lux).select { |c| CHANNEL_NAME.match?(c) }

        return [403, headers_html, ['no channels for this session']] if channels.empty?

        last_event_id = lux.request.env['HTTP_LAST_EVENT_ID']
        last_event_id = nil unless last_event_id.to_s =~ /\A\d+\z/

        [200, headers_sse, Lux::Response::Sse::StreamBody.new(channels, last_event_id)]
      end

      def self.serve body
        [200, headers_js, [body]]
      end

      def self.headers_js
        {
          'content-type'  => 'application/javascript; charset=utf-8',
          'cache-control' => 'private, no-cache, no-store',
        }
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
