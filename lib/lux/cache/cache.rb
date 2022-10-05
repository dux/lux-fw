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

    def write key, data, ttl=nil
      key = generate_key key
      ttl = ttl.to_i if ttl
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
        Lux.log " Cache.fetch.set #{opts.compact.to_jsonc}:#{key.trim(30)}, at: #{Lux.app_caller}".red

        Marshal.dump data
      end

      Marshal.load data
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
        elsif el.respond_to?(:created_at)
          keys.push el.created_at
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
