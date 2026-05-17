# https://www.rubydoc.info/github/mperham/dalli/Dalli/Client#set-instance_method

module Lux
  class Cache
    class MemcachedServer
      def initialize
        require 'dalli'
        # Honor MEMCACHE_SERVERS (Dalli convention) so containerized apps can
        # reach a memcached on the host (e.g. via docker bridge IP).
        servers = ENV['MEMCACHE_SERVERS'].to_s.strip
        servers = '127.0.0.1:11211' if servers.empty?
        @server = Dalli::Client.new(servers, { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 24.hours })
      end

      def set key, data, ttl = nil
        @server.set key, data, ttl
      end

      def get key
        @server.get key
      end

      def delete key
        @server.delete key
      end

      def get_multi *args
        @server.get_multi *args
      end

      def fetch key, ttl = nil, &block
        @server.fetch key, ttl, &block
      end

      def clear
        @server.flush_all
      end
    end
  end
end
