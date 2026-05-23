module Lux
  class Browser
    # Handles requests under /lux/*. Called from Application#render_base
    # before route resolution.
    #
    #   /lux/client.js             -> Lux::Browser.client_js (all modules)
    #   /lux/client.js?modules=sse,api -> Lux::Browser.client_js(:sse, :api)
    #   /lux/<module>.js           -> Lux::Browser.client_js(:<module>)  (just that one + core)
    module Mount
      JS_PATH ||= %r{\A/lux/(?<name>[a-z0-9_]+)\.js\z}

      # Returns a Rack triplet, or nil if the path doesn't match anything we serve.
      def self.handle lux
        path = lux.request.path_info
        return nil unless path.start_with?('/lux/')

        if path == '/lux/client.js'
          mods = lux.request.params['modules'].to_s.split(',').map(&:to_sym).reject(&:empty?)
          return serve(Lux::Browser.client_js(*mods))
        end

        if m = JS_PATH.match(path)
          name = m[:name].to_sym
          return [404, headers_html, ['unknown lux module']] unless Lux::Browser.registered?(name)
          return serve(Lux::Browser.client_js(name))
        end

        nil
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
    end
  end
end
