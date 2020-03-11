# frozen_string_literal: true

module Lux
  class Current
    # set to true if user is admin and you want him to be able to clear caches in production
    attr_accessor :can_clear_cache

    attr_accessor :session, :locale
    attr_reader   :request, :response, :nav, :var

    def initialize env=nil, opts={}
      env   ||= '/mock'
      env     = ::Rack::MockRequest.env_for(env) if env.is_a?(String)
      request = ::Rack::Request.new env

      # fix params if defined
      if opts.keys.length > 0
        opts = opts.to_ch [:qs, :query_string, :post, :request_method, :method, :session, :cookies]

        if opts[:post]
          opts[:method] = 'POST'
          opts[:qs]     = opts[:post]
        end

        opts[:query_string]   ||= opts[:qs]
        opts[:request_method] ||= opts[:method]
      end

      # reset page cache
      Thread.current[:lux] = self

      # overload request method
      request.env['REQUEST_METHOD'] = opts[:request_method].to_s.upcase if opts[:request_method]

      # set cookies
      request.cookies.merge opts[:cookies] if opts[:cookies]

      # merge qs if present
      request.params.merge! opts[:query_string] if opts[:query_string]

      # remove empty paramsters in GET request
      if request.request_method == 'GET'
        for el in request.params.keys
          request.params.delete(el) if request.params[el].blank?
        end
      end

      # patch parans to support indiferent access 😈
      request.instance_variable_set(:@params, request.params.to_ch) if request.params.keys.length > 0

      Lux::Current::EncryptParams.decrypt request.params
      ap request.params if request.post? && Lux.config(:log_to_stdout)

      # base vars
      @files_in_use = []
      @response     = Lux::Response.new
      @request      = request
      @session      = Lux::Current::Session.new request
      @nav          = Lux::Application::Nav.new request
      @var          = {}.to_ch

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
    def cache key, opts = {}
      if opts[:ttl]
        # cache globaly if ttl provided
        Lux.cache.fetch(key, opts) { yield }
      else
        data = @var[:cache] ||= {}
        data = @var[:cache][key]
        return data if data
        @var[:cache][key] = yield
      end
    end

    # Set Lux.current.can_clear_cache = true in production for admins
    def no_cache?
      @request.env['HTTP_CACHE_CONTROL'].to_s.downcase == 'no-cache' && can_clear_cache ? true : false
    end

    # Execute action once per page
    def once id=nil, data=nil, &block
      id ||= Digest::SHA1.hexdigest caller[0] if block

      @once_hash ||= {}
      return if @once_hash[id]
      @once_hash[id] = true

      block_given? ? yield : data
    end

    # Generete unique ID par page render
    def uid num_only=false
      Thread.current[:lux][:uid_cnt] ||= 0
      num = Thread.current[:lux][:uid_cnt] += 1
      num_only ? num : "uid_#{num}"
    end

    # Get or check current session secure token
    def secure_token token=nil
      generated = Crypt.sha1(request.ip)
      return generated == token if token
      generated
    end

    # Add to list of files in use
    def files_in_use file=nil
      if block_given?
        return yield(file) unless @files_in_use.include?(file)
      end

      return @files_in_use unless file
      return unless Lux.config(:log_to_stdout)

      file = file.sub './', ''

      if @files_in_use.include?(file)
        true
      else
        @files_in_use.push file
        false
      end
    end
  end
end

