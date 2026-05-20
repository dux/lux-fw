module Lux
  class Cache
    class MemoryServer
      # Sweep expired entries every N writes so long-running processes don't
      # leak keys that were written with a TTL and never read again.
      SWEEP_EVERY ||= 256

      @@lock = Mutex.new
      @@ram_cache = {}
      @@ttl_cache = {}
      @@writes_since_sweep = 0

      def set key, data, ttl=nil
        @@lock.synchronize do
          @@ttl_cache[key] = Time.now.to_i + ttl if ttl
          @@ram_cache[key] = data

          @@writes_since_sweep += 1
          sweep_expired if @@writes_since_sweep >= SWEEP_EVERY
        end
        data
      end

      def get key
        @@lock.synchronize do
          if ttl_check = @@ttl_cache[key]
            return nil if ttl_check < Time.now.to_i
          end

          @@ram_cache[key]
        end
      end

      def fetch key, ttl=nil
        data = get key
        return data if data
        set(key, yield, ttl)
      end

      def delete key
        @@lock.synchronize do
          !!@@ram_cache.delete(key)
        end
      end

      def get_multi(*args)
        @@lock.synchronize do
          @@ram_cache.select{ |k,v| args.index(k) }
        end
      end

      def clear
        @@lock.synchronize do
          @@ram_cache = {}
          @@ttl_cache = {}
          @@writes_since_sweep = 0
        end
      end

      private

      # Caller must hold @@lock.
      def sweep_expired
        now = Time.now.to_i
        expired = @@ttl_cache.select { |_, expires_at| expires_at < now }.keys
        expired.each do |k|
          @@ttl_cache.delete k
          @@ram_cache.delete k
        end
        @@writes_since_sweep = 0
      end
    end
  end
end
