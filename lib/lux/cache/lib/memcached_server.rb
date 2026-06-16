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
        # memcached is localhost-only here, so Marshal's deserialization risk
        # doesn't apply; opt in explicitly to silence Dalli's default warning
        # and keep full Ruby-object round-tripping (JSON would mangle symbols/Time/models).
        @server = Dalli::Client.new(servers, namespace: namespace, compress: true, expires_in: 24.hours, serializer: Marshal)
      end

      # memcached/Dalli cannot tell a stored nil from a missing key, so a
      # cached nil/false would be re-computed every time. Store nil as a
      # sentinel and translate it back transparently on every read path.
      NIL_MARK ||= '__lux_cache_nil__'

      def set key, data, ttl = nil
        @server.set key, (data.nil? ? NIL_MARK : data), ttl
        data
      end

      def get key
        val = @server.get key
        val == NIL_MARK ? nil : val
      end

      def delete key
        @server.delete key
      end

      def get_multi *args
        @server.get_multi(*args).transform_values { |v| v == NIL_MARK ? nil : v }
      end

      def fetch key, ttl = nil
        raw = @server.get key
        return (raw == NIL_MARK ? nil : raw) unless raw.nil?
        value = yield
        set key, value, ttl
        value
      end

      def clear
        @server.flush_all
      end
    end
  end
end
