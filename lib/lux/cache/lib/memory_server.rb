module Lux
  class Cache
    class MemoryServer
      # Sweep expired entries every N writes so long-running processes don't
      # leak keys that were written with a TTL and never read again.
      SWEEP_EVERY ||= 256

      # sentinel for "key absent" so fetch can cache a real nil/false value
      MISS ||= Object.new

      def initialize
        @lock = Mutex.new
        @ram_cache = {}
        @ttl_cache = {}
        @writes_since_sweep = 0
      end

      def set key, data, ttl=nil
        @lock.synchronize do
          @ttl_cache[key] = Time.now.to_i + ttl if ttl
          @ram_cache[key] = data

          @writes_since_sweep += 1
          sweep_expired if @writes_since_sweep >= SWEEP_EVERY
        end
        data
      end

      def get key
        @lock.synchronize do
          if ttl_check = @ttl_cache[key]
            if ttl_check < Time.now.to_i
              @ram_cache.delete key
              @ttl_cache.delete key
              return nil
            end
          end

          @ram_cache[key]
        end
      end

      # honor a cached nil/false: check key presence, not truthiness, so a
      # block that legitimately returns nil is stored and not re-run.
      def fetch key, ttl=nil
        hit = @lock.synchronize do
          if (expires_at = @ttl_cache[key]) && expires_at < Time.now.to_i
            @ram_cache.delete key
            @ttl_cache.delete key
            MISS
          elsif @ram_cache.key?(key)
            @ram_cache[key]
          else
            MISS
          end
        end

        return hit unless hit.equal?(MISS)
        set(key, yield, ttl)
      end

      def delete key
        @lock.synchronize do
          @ttl_cache.delete key
          !!@ram_cache.delete(key)
        end
      end

      def get_multi(*args)
        @lock.synchronize do
          @ram_cache.select{ |k,v| args.index(k) }
        end
      end

      def clear
        @lock.synchronize do
          @ram_cache = {}
          @ttl_cache = {}
          @writes_since_sweep = 0
        end
      end

      private

      # Caller must hold @lock.
      def sweep_expired
        now = Time.now.to_i
        @ttl_cache.delete_if do |k, expires_at|
          if expires_at < now
            @ram_cache.delete k
            true
          end
        end
        @writes_since_sweep = 0
      end
    end
  end
end
