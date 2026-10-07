module Lux
  class Response
    # CORS response headers + automatic preflight handling.
    #
    # Usage from inside a controller action or `before` callback:
    #
    #   response.cors :all
    #   response.cors origins: ['https://app.example.com', /\Ahttps:\/\/[\w-]+\.example\.com\z/],
    #                 methods: %i[get post],
    #                 headers: %w[Authorization Content-Type],
    #                 credentials: true,
    #                 max_age: 600
    #
    # `:all` is shorthand for "permissive": sends "*", allows the common verbs
    # and headers, max-age 600. Cannot be combined with `credentials: true` -
    # the spec forbids "*" + credentials. A listed origin is a String compared
    # exactly or a Regexp (anchor it); the matching Origin is echoed back.
    #
    # When the request is a CORS preflight (OPTIONS + Access-Control-Request-Method),
    # this method also sets status 204 + empty body so the response is complete
    # without the action body running. The dispatcher's OPTIONS short-circuit
    # in Application#render_base now only fires for non-preflight OPTIONS, so
    # preflight requests flow through `before` callbacks and reach this code.
    module Cors
      DEFAULT_METHODS ||= %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze
      DEFAULT_HEADERS ||= %w[Authorization Content-Type X-Requested-With].freeze
      DEFAULT_MAX_AGE ||= 600

      def self.apply response, *args,
                     origins: nil, methods: nil, headers: nil,
                     credentials: false, max_age: nil, expose: nil

        if args.first == :all
          raise ArgumentError, 'cors :all cannot be combined with credentials:true (CORS spec forbids "*" with credentials)' if credentials
          origins ||= '*'
          methods ||= DEFAULT_METHODS
          headers ||= DEFAULT_HEADERS
          max_age ||= DEFAULT_MAX_AGE
        end

        request      = response.current.request
        origin_value = resolve_origin(request, origins)
        h            = response.headers

        if origin_value
          h['access-control-allow-origin'] = origin_value
          h['vary'] = vary_with(h['vary'], 'Origin') if origin_value != '*'
        end

        h['access-control-allow-methods']     = format_list(methods) if methods
        h['access-control-allow-headers']     = format_list(headers) if headers
        h['access-control-expose-headers']    = format_list(expose)  if expose
        h['access-control-allow-credentials'] = 'true'                if credentials
        h['access-control-max-age']           = max_age.to_s          if max_age

        if preflight?(request)
          response.status 204
          response.body ''
        end
      end

      def self.preflight? request
        request.request_method == 'OPTIONS' &&
          request.env['HTTP_ACCESS_CONTROL_REQUEST_METHOD']
      end

      # "*"        -> "*"
      # nil        -> nil (no header)
      # list / str -> echo Origin if a String equals it or a Regexp matches it, else nil
      def self.resolve_origin request, origins
        return nil if origins.nil?
        return '*' if origins == '*'

        req = request.env['HTTP_ORIGIN'].to_s
        return nil if req.empty?

        allowed = Array(origins).any? { _1.is_a?(Regexp) ? _1.match?(req) : _1.to_s == req }
        allowed ? req : nil
      end

      def self.format_list value
        return value.to_s unless value.is_a?(Array)
        value.map { |v| v.is_a?(Symbol) ? v.to_s.upcase : v.to_s }.join(', ')
      end

      def self.vary_with existing, value
        items = (existing || '').split(',').map(&:strip).reject(&:empty?)
        items << value unless items.include?(value)
        items.join(', ')
      end

      private_class_method :preflight?, :resolve_origin, :format_list, :vary_with
    end
  end
end
