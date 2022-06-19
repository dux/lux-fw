module Lux
  class Cache
    class MemoryServer
      @@lock = Mutex.new
      @@ram_cache = {}
      @@ttl_cache = {}

      def set key, data, ttl=nil
        @@lock.synchronize do
          @@ttl_cache[key] = Time.now.to_i + ttl if ttl
          @@ram_cache[key] = data
        end
      end

      def get key
        if ttl_check = @@ttl_cache[key]
          return nil if ttl_check < Time.now.to_i
        end

        @@ram_cache[key]
      end

      def fetch key, ttl=nil
        data = get key
        return data if data
        set(key, yield, ttl)
      end

      def delete key
        @@lock.synchronize do
          @@ram_cache.delete(key)
        end
      end

      def get_multi(*args)
        @@ram_cache.select{ |k,v| args.index(k) }
      end
    end
  end
end
