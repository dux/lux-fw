require 'set'

module Lux
  class Current
    OPTS ||= Struct.new 'LuxCurrentOpts', :params, :post, :http_method, :session, :cookies, :query_string

    # set to true if user is admin and you want him to be able to clear caches in production
    attr_accessor :can_clear_cache

    attr_accessor :session, :locale, :error
    attr_reader   :request, :response, :nav, :route, :var, :env, :params

    # Body-only params: parsed POST/PUT/PATCH body, no GET/route merge,
    # no EncryptParams processing. Lazy; falls back to request.POST for form-encoded
    # bodies and to the JSON-parsed body for application/json. @opt.post wins
    # (set by Lux.render.post mocks).
    def post
      @post ||= begin
        raw = if @opt.post
          @opt.post
        elsif @request.media_type == 'application/json'
          body = @request.body.tap(&:rewind).read
          JSON.parse(body, symbolize_names: true) rescue {}
        else
          @request.POST.dup
        end
        (raw || {}).to_lux_hash
      end
    end

    def initialize env = nil, opts = {}
      @env     = env || '/mock'
      @env     = ::Rack::MockRequest.env_for(env) if env.is_a?(String)
      @request = ::Rack::Request.new @env

      @opt = OPTS.new
      if opts.keys.length > 0
        @opt = OPTS.new **opts.slice(:params, :post, :session, :cookies, :query_string).merge(
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

    # Get or check current session secure token
    def secure_token token = nil
      generated = Lux::Utils::Crypt.sha1(self.ip)
      token ? (generated == token) : generated
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

      if @files_in_use.include?(file)
        true
      else
        Lux.log ' ' + file.sub('//', '/').colorize(:magenta)

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

    def ip
      request.env['HTTP_CF_CONNECTING_IP'] || # will not work with cloudflare if removed
      request.env['HTTP_X_FORWARDED_FOR'] ||
      request.env['REMOTE_ADDR'] ||
      '127.0.0.1'
    end

    # Per-request browser-state accumulator. Chain-set keys land in window.<root>
    # via `lux.browser.script_tag` in the layout. See lib/lux/browser/.
    def browser
      @browser ||= Lux::Browser.new
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

    def session_sid
      User.current&[:session_sid]
    end

    def user
      User.current
    end

    # Lux::Utils::Crypt.encrypt('secret', ttl:1.hour, password:'pa$$w0rd')
    private

    def prepare_params
      @params = (@request.params.dup || {}).to_lux_hash
      @params.merge! @opt.query_string if @opt.query_string

      # remove empty parametars in GET request
      if request.request_method == 'GET'
        for el in @params.keys
          @params.delete(el) if @params[el].blank?
        end
      end

      Lux::Current::EncryptParams.decrypt @params
    end
  end
end

