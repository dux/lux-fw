module Lux
  class Cache
    class SqliteServer
      def initialize path = nil
        file = Pathname.new path || './tmp/lux_cache.sqlite'
        # file.delete if file.exist?
        @db = Sequel.sqlite file.to_s

        unless @db.tables.include?(:cache)
          @db.create_table :cache do
            primary_key :id
            datetime :valid_to
            string   :key
            blob     :value
          end

          @db.add_index :cache, :key
        end

        @cache = @db[:cache]
      end

      def set key, data, ttl = nil
        self.delete key
        ttl ||= 60 * 60 * 24
        value = Base64.encode64 Marshal.dump(data)
        @cache.insert(key: key, value: value, valid_to: Time.now + ttl.seconds)
        data
      end

      def get key
        row = @cache.where(key: key).to_a.first

        if row
          if row[:valid_to] >= Time.now
            Marshal.load Base64.decode64 row[:value]
          else
            self.delete key
          end
        end
      end

      def fetch key, ttl = nil
        self.get(key) || self.set(key, yield, ttl)
      end

      def delete key
        @cache.where(key: key).delete
        nil
      end

      def get_multi *args
        data = @cache.where(key: args).all
        data.inject({}) {|t, el| t[el[:key]] = Marshal.load Base64.decode64(el[:value]); t}
      end

      def clear
        @cache.truncate
      end
    end
  end
end
