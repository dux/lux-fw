module Lux
  class Cache
    OPTS ||= Struct.new(:ttl, :force, :if, :delete_if_empty)

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
      if Lux.ctx.no_cache?
        nil
      else
        key = generate_key key
        log_get "Cache.read #{key}"
        @server.get(key)
      end
    end
    alias :get :read

    def read_multi *keys
      map = keys.to_h { [generate_key(_1), _1] }
      @server.get_multi(*map.keys).transform_keys { map[_1] }
    end
    alias :get_multi :read_multi

    def write key, data, ttl = nil
      ttl = ttl[:ttl] || ttl[:expires_at] if ttl.is_hash?
      ttl = ttl.to_i if ttl
      key = generate_key key
      Lux.log { %[ Cache.write "#{key}", at: #{Lux.app_caller}].colorize(:yellow) } if Lux.debug?
      @server.set(key, data, ttl)
    end
    alias :set :write

    # 2nd arg is kept for backwards-compat; ignored
    def delete key, _data=nil
      key = generate_key key

      Lux.log do
        if Lux.ctx.var[:show_cache_log]
          %[ Cache.delete "#{key}", at: #{Lux.app_caller}].colorize(:yellow)
        end
      end

      @server.delete(key)
    end

    def fetch key, opts = {}
      key = generate_key key

      opts = { ttl: opts } unless opts.is_hash?
      opt = OPTS.new(**opts)

      return yield(key) if opt.if.is_a?(FalseClass)

      opt.ttl     = opt.ttl.to_i if opt.ttl
      opt.force ||= Lux.ctx.no_cache? unless opt.force.class == FalseClass

      @server.delete key if opt.force

      if Lux.debug?
        log_key_name = "Cache.fetch.get #{opt.to_h.compact.to_jsonc}:#{key.trim(30)}"
        log_get log_key_name
      end

      data = @server.fetch(key, opt.ttl) do
        yield.tap { Lux.log { " #{log_key_name}, at: #{Lux.app_caller}".colorize(:yellow) } if Lux.debug? }
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

    # cooperative rate limit (NOT a mutex): a caller within `time` seconds of
    # the last run sleeps out the remainder, then runs the block.
    # Two concurrent callers may race past the check; for true mutual exclusion
    # use a backend with atomic add/setnx and adapt accordingly.
    # Lux.cache.lock 'some-key', 3 do ...
    def lock key, time
      key  = "syslock-#{key}"
      last = @server.get(key).to_f
      wait = time - (Time.now.to_f - last)
      sleep wait if wait > 0 && wait <= time
      @server.set(key, Time.now.to_f, time.ceil)
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
        else
          keys.push el.to_s
        end
      end

      Lux::Utils::Crypt.sha1(keys.join('-'))
    end

    def []= key, value
      write key, value
      value
    end

    def [] key
      read key
    end

    private

    def log_get name
      return unless Lux.debug? && Lux.ctx.request

      var = Lux.ctx.var
      var[:show_cache_log] = true if Lux.ctx.params[:lux_show_cache_get]

      if var[:show_cache_log]
        Lux.log { " Cache.get #{name}, at: #{Lux.app_caller}".colorize(:green) }
      elsif Lux.ctx.once(:show_cache_log)
        Lux.log { " Cache.get info is suppressed: enable? -> #{Lux.ctx.nav.base}#{Lux.ctx.request.path}?lux_show_cache_get=true".colorize(:green) }
      end
    end
  end
end
