module Lux
  OPTS ||= Struct.new 'LuxCacheOpts', :ttl, :force, :if, :unless, :speed, :delete_if_empty

  class Cache
    def initialize server_name = nil
      self.server= server_name || :memory
    end

    # sert cache server
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
      ttl = ttl[:ttl] || ttl[:expires_at] if ttl.class == Hash
      ttl = ttl.to_i if ttl
      key = generate_key key
      Lux.log %[ Cache.write "#{key}", at: #{Lux.app_caller}].colorize(:yellow)
      @server.set(key, data, ttl)
    end
    alias :set :write

    def delete key, data=nil
      key = generate_key key

      Lux.log do
        if Lux.config[:show_cache_log]
          %[ Cache.delete "#{key}", at: #{Lux.app_caller}].colorize(:yellow)
        end
      end

      Lux.current.var[:cache] ||= {}
      Lux.current.var.cache.delete key
      @server.delete(key)
    end

    def fetch key, opts = {}
      key = generate_key key

      opts = { ttl: opts } unless opts.is_a?(Hash)
      opts = OPTS.new **opts

      return yield(key) if opts.if.is_a?(FalseClass)

      opts.ttl     = opts.ttl.to_i if opts.ttl
      opts.force ||= Lux.current.no_cache? unless opts.force.class == FalseClass

      @server.delete key if opts.force

      log_key_name = "Cache.fetch.get #{opts.compact.to_jsonc}:#{key.trim(30)}"
      log_get log_key_name

      data = @server.fetch key, opts.ttl do
        opts.speed = Lux.speed { data = yield }
        Lux.log " #{log_key_name}, at: #{Lux.app_caller}".colorize(:yellow)
        Marshal.dump data
      end

      Marshal.load(data).tap do |out|
        if opts.delete_if_empty && out.empty?
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

    # lock execution of a block for some time and allow only once instance running in time slot
    # give some block 3 seconds to run, if another instance executes same block after 1 second, if will wait 2 seconds till it wil continue
    # Lux.cache.lock 'some-key', 3 do ...
    def lock key, time
      key = "syslock-#{key}"
      cache_time = Lux.cache.get key

      if cache_time && cache_time > (Time.monotonic - time)
        diff = time - (Time.monotonic - cache_time)
        sleep diff.abs
      else
        Lux.cache.set(key, Time.monotonic, time)
      end

      yield
    end

    def clear
      @server.clear
    end

    def is_available?
      set('lux-test', 9)
      get('lux-test') == 9
    end

    def generate_key *data
      if data[0].class == String && !data[1]
        return data[0]
      end

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

      key = keys.join('-')

      @key = Crypt.sha1(key)
    end

    def []= key, value
      @server.set key.to_s, value
      value
    end

    def [] key
      @server.get key.to_s
    end

    def log_get name
      if Lux.env.log?
        if Lux.current.params[:lux_show_cache_get]
          Lux.config[:show_cache_log] = true
        end

        if Lux.config[:show_cache_log]
          Lux.log " Cache.get #{name}, at: #{Lux.app_caller}".colorize(:green)
        else
          if Lux.current.once(:show_cache_log)
            Lux.log " Cache.get info is suppressed: enable? -> #{Lux.current.nav.base}#{Lux.current.request.path}?lux_show_cache_get=true".colorize(:green)
          end
        end
      end
    end
  end
end
