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
        # Stable namespace across deploys: prefer explicit env, else hash of app root.
        # Avoid __FILE__-based hashing because gem install paths change between deploys
        # and would silently invalidate the entire cache.
        namespace = ENV['MEMCACHE_NAMESPACE']
        namespace = Digest::MD5.hexdigest(Lux.root.to_s)[0,6] if namespace.to_s.empty?
        @server = Dalli::Client.new(servers, namespace: namespace, compress: true, expires_in: 24.hours)
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
