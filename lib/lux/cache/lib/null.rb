module Lux
  class Cache
    class NullCache
      def set key, data, ttl=nil
        data
      end

      def get key
        nil
      end

      def fetch key, ttl=nil
        yield
      end

      def delete key
        nil
      end

      def get_multi *args
        {}
      end
    end
  end
end
