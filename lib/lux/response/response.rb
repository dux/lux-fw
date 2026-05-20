# Common usage:
#   response.header 'x-blah', 123
#   response.body = 'hello'
#   response.status = 500
#   response.cache.public  = true
#   response.cache.max_age = 10.minutes
#   response.cache_public  10.minutes        # shortcut
#   response.no_store                        # disable cache + cookies
module Lux
  class Response
    attr_reader   :render_start
    attr_accessor :headers, :cookies

    def initialize
      @render_start = Time.monotonic
      @headers      = Lux::Response::Header.new
      @cache        = Lux::Response::CachePolicy.new(self)
    end

    def current
      Lux.current
    end

    def cache
      @cache
    end

    # header['x-foo']
    # header 'x-foo', 'bar'
    # header @hash
    def header *args
      if args.first
        if args.first.is_a?(Hash)
          args.first.each { |k, v| header k, v.to_s if k && v }
        else
          key = args.first.to_s.downcase
          @headers[key] = args[1].to_s if args[1] != :_
          @headers[key]
        end
      end

      @headers
    end

    # back-compat readers/setters (delegate to cache policy)
    def max_age
      @cache.max_age
    end

    def max_age= age
      @cache.max_age = age.to_i
    end

    def stale_while_revalidate= swr
      @cache.stale_while_revalidate = swr
    end

    def public?
      @cache.public?
    end

    def public= value
      @cache.public = value
    end

    def cached?
      @cache.cached?
    end

    # shortcut: public cache for N seconds
    def cache_public age
      @cache.public  = true
      @cache.max_age = age.to_i
    end

    # shortcut: response is sensitive, no caching, no cookies
    def no_store
      @cache.no_store = true
    end

    # http 103
    def early_hints link = nil, type = nil
      @early_hints ||= []
      hint = [link, type]
      @early_hints.push hint if type && !@early_hints.include?(hint)
      @early_hints
    end

    def etag *args
      unless @headers['etag']
        key = '"%s"' % Lux.cache.generate_key([current.request.url, args])
        key = 'W/%s' % key unless @cache.public?
        @headers['etag'] = key
      end

      if !@status && !current.no_cache? && current.request.env['HTTP_IF_NONE_MATCH'] == @headers['etag']
        if Lux.env.reload?
          Lux.log { " * etag match at #{Lux.app_caller || ':lux'} (skiping for env.reload?)" } unless current.nav.format
        else
          Lux.log { ' * etag match' }
          @status = 304
          @body   = ''
          true
        end
      else
        false
      end
    end

    # response.status            # get
    # response.status = 404      # set
    # response.status 404        # set
    def status num = Lux::UNSET
      return @status if num.equal?(Lux::UNSET)

      unless num.is_numeric?
        Lux.info %[LUX error: Not numeric status code "#{num}", reverting to 400]
        num = 400
      end

      @status = num
    end
    alias :status= :status

    def halt status = nil, msg = nil
      @status = status || 400
      @body   = msg if msg
    end

    # response.body                          # get
    # response.body = 'foo'                  # set
    # response.body 'foo'                    # set (back-compat)
    # response.body 'foo', status: 400       # set with side-effects (back-compat)
    # response.body { |old| transform(old) } # transform existing body
    def body data = Lux::UNSET, opts = nil
      if block_given?
        @body = yield @body
        return @body
      end

      return @body if data.equal?(Lux::UNSET)

      if opts.is_a?(Hash)
        opts.each { |k, v| public_send k, *v }
      end

      unless @body
        # eager serialize hash bodies so callers see the final string
        @body = data.is_a?(Hash) ? JSON.generate(data) : data
      end
      @body
    end
    alias :body= :body

    def body?
      !!@body
    end

    # response.content_type            # get
    # response.content_type = :js      # set (always overrides)
    # response.content_type :js        # set
    def content_type in_type = Lux::UNSET
      return @content_type if in_type.equal?(Lux::UNSET)

      in_type = :js if in_type == :javascript

      if in_type.is_a?(Symbol)
        type = ::Rack::Mime.mime_type(".#{in_type}", nil)
        raise ArgumentError.new('Bad content type: %s' % in_type) unless type
      else
        type = in_type
      end

      @content_type = type
    end
    alias :content_type= :content_type

    def flash message = nil
      @flash ||= Flash.new current.session[:lux_flash]
      message ? @flash.error(message) : @flash
    end

    def send_file file, opts = {}
      ::Lux::Response::File.new(opts.merge(file: file)).send
    end

    # redirect_to '/foo'
    # redirect_to :back, info: 'bar ...'
    def redirect_to where, opts = {}
      Lux.log { ' Redirected to "%s" from: %s' % [where, Lux.app_caller] }

      opts = { info: opts } if opts.is_a?(String)

      if where == :self
        where = current.request.path
      elsif where == :back
        where  = current.request.env['HTTP_REFERER'].or('/')
      elsif where[0,1] == '?'
        where  = "#{current.request.path}#{where}"
      # elsif !where.include?('://')
      #   where = current.host + where
      end

      if where.start_with?('/') || opts.delete(:redirect_tracker)
        redirect_var = Lux.config[:redirect_var] || :_r
        url = Url.new where
        url[redirect_var] = current.request.params[redirect_var].to_i + 1

        where = if opts.delete(:silent)
          url.delete redirect_var
          url.to_s
        else
          url[redirect_var].to_i > 3 ? '/' : url.to_s
        end
      end

      @status = opts.delete(:status) || 302
      opts.map { |k,v| flash.send(k, v) }

      escaped_where = where.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'").gsub('<', '\\u003c').gsub('>', '\\u003e')

      @body = <<~PAGE
        <html>
          <head>
            <title>redirecting</title>
          </head>
          <body>
            <p>redirecting to #{where.gsub('<', '&lt;').gsub('>', '&gt;')}</p>
            <p>#{opts.values.join("\n")}</p>
            <script>location.href = '#{escaped_where}'</script>
          </body>
        </html>
      PAGE

      @headers['location'] = where
      @headers['access-control-expose-headers'] ||= 'Location'

      # if we do not have this here, controller will proceed executing code after redirect_to
      throw :done
    end

    def permanent_redirect_to where
      redirect_to where, status: 301
    end

    # auth { |user, pass| [user, pass] == ['foo', 'bar'] }
    def auth realm: nil, message: nil
      if auth = current.request.env['HTTP_AUTHORIZATION']
        credentials = auth.to_s.split('Basic ', 2)[1].unpack("m*").first.split(':', 2)
        return true if yield *credentials
      end

      header('WWW-Authenticate', 'Basic realm="%s"' % realm.or('default'))
      self.status = 401
      @body = message || 'HTTP 401 Authorization needed'
    end

    def render app = nil
      write_response_body

      # Fire Application#after BEFORE headers are written so callbacks can mutate
      # @body (translations, HTML rewrites, etc.) and content-length / etag are
      # computed against the final body. Flash added in :after also makes the cookie.
      if app
        app.run_callback :after
      end

      write_response_header

      @status ||= 200

      Lux.log do
        log_data  = " #{@status}, #{@data.to_s.length}, #{(@body.bytesize.to_f/1024).round(1)}kb, #{@headers['x-lux-speed']}"
        log_data += " (#{current.request.url})" if current.nav.format

        [200, 304].include?(@status) ? log_data : log_data.colorize(:magenta)
      end

      if current.request.request_method == 'HEAD' || [204, 304].include?(@status.to_i)
        @body = ''
      end

      [@status, @headers.to_h, [@body]]
    end

    def rack klass, mount_at: nil
      env = current.env
      if mount_at
        env = env.merge(
          'SCRIPT_NAME' => mount_at,
          'PATH_INFO'   => env['PATH_INFO'].delete_prefix(mount_at).then { |p| p.empty? ? '/' : p }
        )
      end
      data = klass.call env
      @headers.merge data[1]
      body data[2].first, status: data[0]
    end

    def is_bot?
      current.request.user_agent.to_s.include?('Googlebot')
    end

    private

    # Persist flash into session, but only if it has content or needs clearing.
    # Avoids dirtying the session on every request just to write an empty flash hash.
    def write_flash_to_session
      flash_hash = flash.to_h
      if flash_hash.keys.any?
        current.session[:lux_flash] = flash_hash
      elsif current.session[:lux_flash]
        current.session.delete(:lux_flash)
      end
    end

    def write_response_body
      # default: empty body + 204
      unless @body
        @status ||= 204
        @body = ''
      end

      # respond as JSON if we recive hash
      if @body.kind_of?(Hash)
        @body = Lux.env.log? ? JSON.pretty_generate(@body) : JSON.generate(@body)

        if current.request.params[:callback]
          @body = "#{current.request.params[:callback]}(#{@body})"
          @content_type ||= 'text/javascript'
        else
          @content_type ||= 'application/json'
        end

        @body += "\n"
      else
        # if somebody sets @content_type, respect that
        # @body = @body.to_s unless @body.kind_of?(String)
        @content_type ||= 'text/plain' if @body[0,1] != '<'
        @content_type ||= 'text/html'
      end
    end

    def write_response_header
      write_flash_to_session

      # flash forces private cache + no max_age
      if flash.to_h.keys.length != 0
        @cache.public  = false
        @cache.max_age = 0
      end

      # cache-control: use cache policy unless caller set explicit header
      @headers['cache-control'] ||= @cache.header_value

      # only emit Set-Cookie when cache policy allows it
      if @cache.allow_cookies? && !is_bot?
        cookie = current.session.generate_cookie
        @headers['set-cookie'] = cookie if cookie
      end

      # Auto-etag only for cacheable 2xx GETs. Redirects (3xx), errors (4xx/5xx)
      # and no-store responses don't benefit from a conditional-GET round-trip,
      # so skipping saves a full-body SHA1 on the response path.
      if current.request.request_method == 'GET' && !@cache.no_store? && @status.to_i < 300
        etag(@body)
      end

      @headers['x-lux-speed']     = "#{((Time.monotonic - @render_start)*1000).round(1)}ms"

      # 304 must not carry content-type / content-length per RFC 7232
      unless @status.to_i == 304
        @headers['content-type'] ||= "#{@content_type}; charset=utf-8"
        @headers['content-length'] = @body.bytesize.to_s
      end
    end
  end
end
