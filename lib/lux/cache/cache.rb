module Lux
  class Cache
    OPTS ||= Struct.new(:ttl, :force, :if, :unless, :speed, :delete_if_empty)

    def initialize server_name = nil
      self.server= server_name || :memory
    end

    # set cache server
    # Lux.cache.server = :memory
    # Lux.cache.server = :memcached
    # Lux.cache.server = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })
    def server= name
      @server =
      if name.is_a?(Symbol)
        require_relative 'lib/%s_server' % name
        @server = ('lux/cache/%s_server' % name).classify.constantize.new
      else
        name
      end
    end

    def server
      @server
    end

    def read key
      if Lux.current.no_cache?
        nil
      else
        key = generate_key key
        log_get "Cache.read #{key}"
        @server.get(key)
      end
    end
    alias :get :read

    def read_multi *args
      @server.get_multi(*args)
    end
    alias :get_multi :read_multi

    def write key, data, ttl = nil
      ttl = ttl[:ttl] || ttl[:expires_at] if ttl.is_hash?
      ttl = ttl.to_i if ttl
      key = generate_key key
      Lux.log { %[ Cache.write "#{key}", at: #{Lux.app_caller}].colorize(:yellow) } if Lux.mode.debug?
      @server.set(key, data, ttl)
    end
    alias :set :write

    # 2nd arg is kept for backwards-compat; ignored
    def delete key, _data=nil
      key = generate_key key

      Lux.log do
        if Lux.current.var[:show_cache_log]
          %[ Cache.delete "#{key}", at: #{Lux.app_caller}].colorize(:yellow)
        end
      end

      Lux.current.var[:cache] ||= {}
      Lux.current.var.cache.delete key
      @server.delete(key)
    end

    def fetch key, opts = {}
      key = generate_key key

      opts = { ttl: opts } unless opts.is_hash?
      opt = OPTS.new(**opts)

      return yield(key) if opt.if.is_a?(FalseClass)

      opt.ttl     = opt.ttl.to_i if opt.ttl
      opt.force ||= Lux.current.no_cache? unless opt.force.class == FalseClass

      @server.delete key if opt.force

      log_key_name = "Cache.fetch.get #{opt.compact.to_jsonc}:#{key.trim(30)}"
      log_get log_key_name

      data = @server.fetch(key, opt.ttl) do
        yield_value = nil
        opt.speed = Lux.speed { yield_value = yield }
        Lux.log { " #{log_key_name}, at: #{Lux.app_caller}".colorize(:yellow) } if Lux.mode.debug?
        yield_value
      end

      data.tap do |out|
        if opt.delete_if_empty && out.respond_to?(:empty?) && out.empty?
          @server.delete key
        end
      end
    end

    # cache only if data is true
    # for example used for security checks, to check if user can access board
    # complex search that is usually true, but if it is false, we want it to not be cached,
    #   because we want it to work once we give user access
    def fetch_if_true key, opts = {}
      if data = self.read(key)
        data
      else
        if data = yield(key)
          self.write key, data, opts
        end
      end
      data
    end

    # cooperative process-local rate limit (NOT a cross-process mutex).
    # Two concurrent callers may race past the check; for true mutual exclusion
    # use a backend with atomic add/setnx and adapt accordingly.
    # Lux.cache.lock 'some-key', 3 do ...
    def lock key, time
      key = "syslock-#{key}"
      cache_time = @server.get(key)

      if cache_time && cache_time > (Time.monotonic - time)
        diff = time - (Time.monotonic - cache_time)
        sleep diff.abs
      end

      @server.set(key, Time.monotonic, time)
      yield
    end

    def clear
      @server.clear
    end

    def is_available?
      k = Lux::Utils::Crypt.sha1('__lux_cache_health__')
      @server.set(k, 9)
      @server.get(k) == 9
    end

    def generate_key *data
      return data[0] if data[0].class == String && !data[1]

      keys = []

      for el in [data].flatten
        keys.push el.class.to_s
        keys.push el.id if el.respond_to?(:id)

        if el.respond_to?(:updated_at)
          keys.push el.updated_at.to_f
        elsif el.respond_to?(:id)
          keys.push el.id
        else
          keys.push el.to_s
        end
      end

      Lux::Utils::Crypt.sha1(keys.join('-'))
    end

    def []= key, value
      @server.set key.to_s, value
      value
    end

    def [] key
      @server.get key.to_s
    end

    private

    def log_get name
      return unless Lux.mode.debug?

      var = Lux.current.var
      var[:show_cache_log] = true if Lux.current.params[:lux_show_cache_get]

      if var[:show_cache_log]
        Lux.log { " Cache.get #{name}, at: #{Lux.app_caller}".colorize(:green) }
      elsif Lux.current.once(:show_cache_log)
        Lux.log { " Cache.get info is suppressed: enable? -> #{Lux.current.nav.base}#{Lux.current.request.path}?lux_show_cache_get=true".colorize(:green) }
      end
    end
  end
end
