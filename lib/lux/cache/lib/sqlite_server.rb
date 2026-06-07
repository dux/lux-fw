module Lux
  class Cache
    class SqliteServer
      def initialize path = nil
        file = Pathname.new(path || './tmp/lux_cache.sqlite')
        FileUtils.mkdir_p(file.dirname)
        @db = Sequel.sqlite file.to_s
        @db.run 'PRAGMA journal_mode=WAL'
        @db.run 'PRAGMA busy_timeout=5000'

        unless @db.tables.include?(:cache)
          @db.create_table :cache do
            primary_key :id
            datetime :valid_to
            String   :key
            blob     :value
            index    :key, unique: true
          end
        end

        @cache = @db[:cache]
      end

      def set key, data, ttl = nil
        ttl ||= 60 * 60 * 24
        value = Base64.encode64 Marshal.dump(data)
        valid_to = Time.now + ttl.seconds
        @cache.insert_conflict(:replace).insert(key: key, value: value, valid_to: valid_to)
        data
      end

      def get key
        row = @cache.where(key: key).first

        if row
          if row[:valid_to] >= Time.now
            Marshal.load Base64.decode64 row[:value]
          else
            self.delete key
            nil
          end
        end
      end

      # honor a cached nil/false: decide on row presence + validity, not on
      # the decoded value's truthiness, so a block returning nil is stored.
      def fetch key, ttl = nil
        row = @cache.where(key: key).first

        if row && row[:valid_to] >= Time.now
          Marshal.load Base64.decode64 row[:value]
        else
          self.delete(key) if row
          self.set(key, yield, ttl)
        end
      end

      def delete key
        @cache.where(key: key).delete
        nil
      end

      def get_multi *args
        data = @cache.where(key: args).where(Sequel.lit('valid_to >= ?', Time.now)).all
        data.inject({}) {|t, el| t[el[:key]] = Marshal.load Base64.decode64(el[:value]); t}
      end

      def clear
        @cache.truncate
      end
    end
  end
end
