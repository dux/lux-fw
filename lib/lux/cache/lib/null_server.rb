module Lux
  class Cache
    class NullServer
      def initialize
        @server = nil
      end

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

      def clear
        true
      end
    end
  end
end
