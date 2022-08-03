module Lux
  class Current
    # set to true if user is admin and you want him to be able to clear caches in production
    attr_accessor :can_clear_cache

    attr_accessor :session, :locale
    attr_reader   :request, :response, :nav, :var, :env, :params, :env

    def initialize env = nil, opts={}
      @env     = env || '/mock'
      @env     = ::Rack::MockRequest.env_for(env) if env.is_a?(String)
      @request = ::Rack::Request.new @env

      # fix params if defined
      if opts.keys.length > 0
        opts = opts.to_hwia :params, :post, :method, :session, :cookies

        if opts[:post]
          opts[:method] = 'POST'
          opts[:params] = opts[:post]
        end
      end

      # reset page cache
      Thread.current[:lux] = self

      # overload request method
      @request.env['REQUEST_METHOD'] = opts[:method].to_s.upcase if opts[:method]

      # set cookies
      @request.cookies.merge opts[:cookies] if opts[:cookies]

      prepare_params opts

      # base vars
      @files_in_use = []
      @response     = Lux::Response.new
      @session      = Lux::Current::Session.new @request
      @nav          = Lux::Application::Nav.new @request
      @var          = {}.to_hwia

      @session.merge! opts[:session] if opts[:session]
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

    # Cache data in scope of current request
    def cache key
      data = @var[:cache] ||= {}
      data = @var[:cache][key]

      if data.nil?
        @var[:cache][key] = yield
      else
        data
      end
    end

    # Set Lux.current.can_clear_cache = true in production for admins
    def no_cache? shallow_check = false
      check = @request.env['HTTP_CACHE_CONTROL'].to_s.downcase == 'no-cache'

      if check
        if shallow_check || Lux.env.dev?
          true
        else
          can_clear_cache ? true : false
        end
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
    def uid num_only=false
      Thread.current[:lux][:uid_cnt] ||= 0
      num = Thread.current[:lux][:uid_cnt] += 1
      num_only ? num : "uid_#{num}_#{(Time.now.to_f*1000).to_i}"
    end

    # Get or check current session secure token
    def secure_token token=nil
      generated = Crypt.sha1(request.ip)
      token ? (generated == token) : generated
    end

    def curl?
      ua = request.env['HTTP_USER_AGENT'].to_s.downcase
      ua.include?('wget/') || ua.include?('curl/')
    end

    # Add to list of files in use
    def files_in_use file=nil
      if block_given?
        return yield(file) unless @files_in_use.include?(file)
      end

      return @files_in_use unless file

      file = file.sub './', ''

      if @files_in_use.include?(file)
        true
      else
        @files_in_use.push file
        false
      end
    end

    # Thread.new but copies env to a thread
    def delay *args
      if block_given?
        lux_env = self.dup
        Thread.new do
          begin
            Thread.current[:lux] = lux_env
            Timeout::timeout(Lux.config.delay_timeout) do
              yield *args
            end
          rescue => e
            Lux.log ['Lux.current.delay error: %s' % e.message, e.backtrace].join($/)
          end
        end
      else
        raise ArgumentError, 'Block not given'
      end
    end

    def encrypt data, opts={}
      opts[:password] ||= request.ip
      opts[:ttl]      ||= 10.minutes
      Crypt.encrypt(data, opts)
    end

    def decrypt token, opts={}
      opts[:password] ||= request.ip
      Crypt.decrypt(token, opts)
    end

    # Crypt.encrypt('secret', ttl:1.hour, password:'pa$$w0rd')
    private

    def prepare_params opts
      # patch params to support indiferent access 😈
      # request.instance_variable_set(:@params, request.params.to_hwia) if request.params.keys.length > 0

      # merge qs if present
      @params = (@request.params.dup || {}).to_hwia
      @params.merge! opts[:query_string] if opts[:query_string]

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

