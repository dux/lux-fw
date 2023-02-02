module Lux
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
      return nil if (Lux.current.no_cache? rescue false)
      key = generate_key key
      @server.get(key)
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
      @server.set(key, data, ttl)
    end
    alias :set :write

    def delete key, data=nil
      key = generate_key key

      Lux.log { %[ Cache.delete "#{key}", at: #{Lux.app_caller}].yellow }

      @server.delete(key)
    end

    def fetch key, opts={}
      key = generate_key key

      opts = { ttl: opts } unless opts.is_a?(Hash)
      opts = opts.to_hwia :ttl, :force, :if, :unless, :speed

      return yield if opts.if.is_a?(FalseClass)

      opts.ttl     = opts.ttl.to_i if opts.ttl
      opts.force ||= Lux.current.try(:no_cache?) unless opts.force.class == FalseClass

      @server.delete key if opts.force

      Lux.log { " Cache.fetch.get #{opts.compact.to_jsonc}:#{key.trim(30)}, at: #{Lux.app_caller}".green }

      data = @server.fetch key, opts.ttl do
        opts.speed = Lux.speed { data = yield }
        Lux.log " Cache.fetch.set #{opts.compact.to_jsonc}:#{key.trim(30)}, at: #{Lux.app_caller}".yellow

        Marshal.dump data
      end

      Marshal.load data
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

      Crypt.sha1(key)
    end

    def []= key, value
      @server.set key.to_s, value
      value
    end

    def [] key
      @server.get key.to_s
    end
  end
end
