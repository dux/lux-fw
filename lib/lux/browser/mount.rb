module Lux
  class Browser
    # Handles requests under /_lux_/*. Called from Application#render_base
    # before route resolution. The /_lux_/ namespace is reserved for the
    # framework - apps must not register routes under it.
    #
    #   /_lux_/client.js             -> Lux::Browser.client_js (all modules)
    #   /_lux_/client.js?modules=sse,api -> Lux::Browser.client_js(:sse, :api)
    #   /_lux_/<module>.js           -> Lux::Browser.client_js(:<module>)  (just that one + core)
    #   /_lux_/stream?channels=a,b   -> SSE stream for the named channels
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

      # SSE endpoint - subscribes to the channels listed in ?channels=a,b,c and
      # streams a text/event-stream until the client disconnects. Channel-level
      # authorization is the app's job (gate via a before_filter or front proxy).
      def self.stream lux
        channels = lux.request.params['channels'].to_s
          .split(',')
          .map(&:strip)
          .reject(&:empty?)
          .select { |c| CHANNEL_NAME.match?(c) }
          .uniq

        return [400, headers_html, ['no channels']] if channels.empty?

        [200, headers_sse, Lux::Response::Sse::StreamBody.new(channels)]
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
