require 'set'

# Rack's xhr? only matches the legacy X-Requested-With header, which fetch()
# never sends. Also treat programmatic fetch/XHR as xhr via Sec-Fetch-Dest:
# browsers set it to 'empty' for fetch/XHR (and 'document' for navigations),
# and JS can't forge it. Falls back to the legacy header for non-browser clients.
class Rack::Request
  def xhr?
    get_header('HTTP_X_REQUESTED_WITH') == 'XMLHttpRequest' ||
      get_header('HTTP_SEC_FETCH_DEST') == 'empty'
  end
end

module Lux
  class Current
    OPTS ||= Struct.new 'LuxCurrentOpts', :params, :post, :http_method, :session, :cookies, :query_string, :headers, :bearer

    # Same charset Rage and most proxies accept for X-Request-Id.
    REQUEST_ID_RE ||= /\A[\w\-@.]{1,128}\z/

    # set to true if user is admin and you want him to be able to clear caches in production
    attr_accessor :can_clear_cache

    attr_accessor :session, :locale, :error
    attr_reader   :request, :response, :nav, :route, :var, :env, :params

    # Query string or body that could not be parsed (Rack::BadRequest,
    # JSON::ParserError). Application#render_base answers it with a 400.
    attr_reader   :malformed_request

    # Body-only params: parsed POST/PUT/PATCH body, no GET/route merge,
    # no EncryptParams processing. Lazy; falls back to request.POST for form-encoded
    # bodies and to the JSON-parsed body for application/json. @opt.post wins
    # (set by Lux.render.post mocks).
    def post
      @post ||= begin
        raw = if @opt.post
          @opt.post
        elsif json_request?
          body = raw_body
          JSON.parse(body, symbolize_names: true) if body.present?
        else
          @request.POST.dup
        end
        (raw || {}).to_lux_hash
      end
    end

    # Request body, read from rack.input once - params, post and Lux::Api all
    # use this copy. Rewound after the read so a Rack app mounted with `map`
    # can still read the stream itself.
    def raw_body
      @raw_body ||= begin
        body = @request.body
        body&.read.to_s.tap { body.rewind if body.respond_to?(:rewind) }
      end
    end

    def json_request?
      @request.media_type == 'application/json'
    end

    def initialize env = nil, opts = {}
      @env     = env || '/mock'
      # body: raw request body for a mock (e.g. a JSON string with a content-type header)
      @env     = ::Rack::MockRequest.env_for(env, input: opts[:body]) if @env.is_a?(String)
      @request = ::Rack::Request.new @env
      # lets a mounted Lux::Api find the Current that already parsed this request
      @request.env['lux.current'] = self

      @opt = OPTS.new
      if opts.keys.length > 0
        @opt = OPTS.new **opts.slice(:params, :post, :session, :cookies, :query_string, :headers, :bearer).merge(
          opts.key?(:method) ? { http_method: opts[:method] } : {}
        )
        if @opt.post
          @opt.http_method = 'POST'
          @opt.params = @opt.post
        end
      end

      # reset page cache
      Thread.current[:lux] = self

      @request.env['REQUEST_METHOD'] = @opt.http_method.to_s.upcase if @opt.http_method
      @request.cookies.merge @opt.cookies if @opt.cookies

      @opt.headers.or({}).each do |k, v|
        key = k.to_s.upcase.tr('-', '_')
        key = "HTTP_#{key}" unless key.start_with?('HTTP_') || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
        @request.env[key] = v
      end

      # shortcut: bearer: 'token' -> Authorization: Bearer token
      @request.env['HTTP_AUTHORIZATION'] = "Bearer #{@opt.bearer}" if @opt.bearer

      prepare_params

      # base vars
      @files_in_use = Set.new
      @response     = Lux::Response.new
      @session      = Lux::Current::Session.new @request
      @nav          = Lux::Application::Nav.new @request
      @route        = Lux::Application::Route.new @nav
      @var          = { cache: {} }.to_lux_hash

      @opt.session.or({}).each {|k,v| @session[k] = v }
    end

    # Param validation errors from the action's `opt` / `params do` contract,
    # as { field => 'Message' }. Only populated for HTML requests - a JSON
    # request halts with 422 instead (see Controller::ParamsDsl). Note that
    # lux.params has already been filtered and coerced by the time this is set,
    # so re-render the form from the submitted values you kept, not from params.
    def param_errors
      @var[:param_errors] || {}
    end

    def [] name
      @var[name]
    end

    def []= name, val
      @var[name] = val
    end

    # Full host with port
    def host
      "#{request.env['rack.url_scheme']}://#{request.host}:#{request.port}".sub(':80','')# rescue 'http://locahost:3000'
    end

    # Lux::Utils::Url wrapper around the current request URL.
    def url
      Lux::Utils::Url.new(@request.url)
    end

    # Cache data in scope of current request
    def cache key
      root = @var[:cache] ||= {}
      data = root[key] # it is array ref because we want to cache nil results too

      unless data
        data = [yield]
        root[key] = data
      end

      data[0]
    end

    # Set Lux.current.can_clear_cache = true in production for admins
    def no_cache?
      if @request.env['HTTP_CACHE_CONTROL'].to_s.downcase == 'no-cache'
        can_clear_cache
      else
        false
      end
    end

    # Execute action once per page
    def once id = nil
      id ||= Digest::SHA1.hexdigest caller[0]

      @once_hash ||= {}
      return false if @once_hash[id]
      @once_hash[id] = true

      if block_given?
        yield || true
      else
        true
      end
    end

    # Generete unique ID par page render
    # current.uid => "uid_123_1668273316128"
    # current.uid(true) => 123
    def uid num_only = false
      Thread.current[:lux][:uid_cnt] ||= 0
      num = Thread.current[:lux][:uid_cnt] += 1
      num_only ? num : "uid_#{num}_#{(Time.now.to_f*1000).to_i}"
    end

    def robot?
      ua = request.env['HTTP_USER_AGENT'].to_s.downcase
      ua.include?('wget/') || ua.include?('curl/')
    end

    def mobile?
      ua = request.env['HTTP_USER_AGENT'].to_s.downcase
      mobile_keywords = %w[
        iphone ipod ipad android mobile blackberry nokia windows phone
        opera mini kindle silk huawei samsung
      ]

      mobile_keywords.any? { |k| ua.include?(k) }
    end

    # Add to list of files in use
    def files_in_use file = nil
      return @files_in_use unless file
      return unless file.class == String

      file = file.sub(Lux.root.to_s + '/', '')
      file = file.sub './', ''
      file = file.sub('//', '/')

      if @files_in_use.include?(file)
        true
      else
        Lux.log ' ' + file.colorize(:magenta)

        @files_in_use.add file
        yield(file) if block_given?
        false
      end
    end

    # Background thread; thin wrapper over Lux.defer.
    # Positional arg becomes the explicit context passed to the block.
    # See Lux.defer for full semantics (clean Lux.current inside the thread,
    # parent context only via the block arg).
    def defer context = nil, &block
      Lux.defer(context: context, &block)
    end

    # Rack#ip reads X-Forwarded-For only behind a trusted (private) proxy and
    # takes the last untrusted hop, so a client cannot spoof it.
    def ip
      request.env['HTTP_CF_CONNECTING_IP'] || # will not work with cloudflare if removed
      request.ip ||
      '127.0.0.1'
    end

    # Upstream X-Request-Id when it is sane, else a fresh one. Echoed in the
    # response header and carried into Lux.defer and exception records.
    def request_id
      @request_id ||= begin
        id = @request.env['HTTP_X_REQUEST_ID'].to_s
        id.match?(REQUEST_ID_RE) ? id : SecureRandom.hex(10)
      end
    end

    # Frozen copy of what background work may need from this request. Safe to
    # hand to another thread, unlike the live Current. Lux.defer passes it to
    # the block and rebuilds the worker's Lux.current from it.
    def snapshot
      {
        request_id:     request_id,
        request_method: request.request_method,
        url:            request.url,
        ip:             ip,
        user:           (user if defined?(::User))
      }.to_lux_hash.freeze
    end

    # Master per-request browser object: header / window / export / channel.
    # See lib/lux/browser/.
    def browser
      @browser ||= Lux::Browser.new
    end

    # Pointer to lux.browser.header (same instance per request).
    def header
      browser.header
    end

    def bearer_token
      auth = request.env['HTTP_AUTHORIZATION'].to_s
      auth.start_with?('Bearer ') ? auth[7..].presence : nil
    end

    def encrypt data, opts={}
      opts[:password] ||= self.ip
      opts[:ttl]      ||= 10.minutes
      Lux::Utils::Crypt.encrypt(data, opts)
    end

    def decrypt token, opts={}
      opts[:password] ||= self.ip
      Lux::Utils::Crypt.decrypt(token, opts)
    end

    # Random per-session id. Set once and persisted in the session cookie;
    # works for guests too - unrelated to the current user.
    def session_sid
      session[:sid] ||= Lux::Utils::Crypt.uid(20)
    end

    def user
      User.current
    end

    # Lux::Utils::Crypt.encrypt('secret', ttl:1.hour, password:'pa$$w0rd')
    private

    def prepare_params
      @params = (request_params.dup || {}).to_lux_hash
      @params.merge! @opt.query_string if @opt.query_string
      # `params:` is the GET shorthand for query_string (for POST it feeds the body, see line ~54)
      @params.merge! @opt.params if @opt.params && request.request_method == 'GET'

      # remove empty parametars in GET request
      if request.request_method == 'GET'
        for el in @params.keys
          @params.delete(el) if @params[el].blank?
        end
      end

      Lux::Current::EncryptParams.decrypt @params
    end

    # Rack raises (EmptyContentError / "bad content body", both EOFError) when a
    # request advertises a multipart/form-data content type but carries an empty
    # or truncated body - e.g. a reverse-proxy auth subrequest (Caddy
    # forward_auth) that copies the Content-Type header without forwarding the
    # body. An empty urlencoded body already degrades to {}, so mirror that for
    # multipart instead of letting it surface as a 500.
    #
    # A JSON object body merges over the query string, the way Rack merges a
    # form body, so `opt` validation sees JSON POSTs too.
    def request_params
      params = @request.params
      body   = json_request? ? raw_body : nil
      body   = JSON.parse(body) if body.present?
      body.is_a?(::Hash) ? params.merge(body) : params
    rescue EOFError
      {}
    rescue Rack::BadRequest, JSON::ParserError => e
      @malformed_request = e
      {}
    end
  end
end

