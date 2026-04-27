require 'sequel/connection_pool/threaded'

module Lux
  module Db
    extend self

    CONNECTIONS ||= {}

    DEFAULT_CONFIG ||= {
      max_connections: 5,
      pool_timeout: 5,
      encoding: 'utf8',
      sslmode: 'disable',
    }.freeze

    class MainProxy < BasicObject
      def method_missing(name, *args, **kwargs, &block)
        ::Lux.db(:main).send(name, *args, **kwargs, &block)
      end

      def respond_to_missing?(name, include_private = false)
        ::Lux.db(:main).respond_to?(name, include_private)
      end

      def class
        ::Sequel::Database
      end
    end

    def connection(name = :main)
      name = name.to_sym
      CONNECTIONS[name] ||= begin
        url = url_for(name)
        raise "Database :#{name} not configured.\n  Set ENV['DB_#{name.to_s.upcase}'] or add to config.yaml:\n  db:\n    #{name}: postgres://localhost/dbname" unless url
        begin
          connect(url)
        rescue Sequel::DatabaseConnectionError
          raise unless Lux.env.rake?
          connect(url.sub(/\/[^\/]+$/, '/postgres'))
        end
      end
    end

    def connections
      CONNECTIONS.values
    end

    def configured_names
      dbs_config.keys.map(&:to_sym)
    end

    def url_for(name)
      name = name.to_sym
      env_key = "DB_#{name.to_s.upcase}"

      url = ENV[env_key]
      return url if url && !url.empty?

      if name == :main
        url = ENV['DB_URL']
        return url if url && !url.empty?
      end

      url = dbs_config[name.to_s]
      return url if url && !url.empty?

      if name == :main
        url = Lux.config[:db_url]
        return url if url && !url.empty?
      end

      nil
    end

    def disconnect_all
      CONNECTIONS.each_value(&:disconnect)
      CONNECTIONS.clear
    end

    def boot!
      configured_names.each do |name|
        url = url_for(name)
        next unless url

        if Lux.env.test?
          url = test_db_url(url)
          ensure_test_db(name, url)
        end

        begin
          CONNECTIONS[name] = connect(url)
          Lux.info "DB :#{name} connected (#{CONNECTIONS[name].opts[:database]})"
        rescue Sequel::DatabaseConnectionError => e
          Lux.info "DB :#{name} connection failed - #{e.message}"
          raise unless Lux.env.rake?
        end
      end
    end

    private

    def dbs_config
      val = Lux.config[:db]
      return {} unless val
      return { 'main' => val } if val.is_a?(String)
      val
    end

    def connect(url)
      config = DEFAULT_CONFIG.dup
      config.merge!(Lux.config[:db_config]) if Lux.config[:db_config].is_a?(Hash)

      db = Sequel.connect(url, config)

      if db.adapter_scheme == :postgres
        db.extension :pg_array, :pg_json
      end

      db
    end

    def test_db_url(url)
      url.sub(/\/([^\/]+)$/) { "/#{$1}_test" }
    end

    def db_name_from_url(url)
      require 'uri'
      URI.parse(url).path.sub('/', '')
    end

    def ensure_test_db(name, test_url)
      test_db = db_name_from_url(test_url)
      source_db = test_db.sub(/_test$/, '')

      return if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{test_db}")

      Lux.info "DB create: %s (schema from %s)" % [test_db, source_db]
      system 'createdb %s 2>/dev/null' % test_db
      system 'pg_dump --schema-only --no-owner --no-privileges %s | psql -q %s > /dev/null 2>&1' % [source_db, test_db]
    end
  end
end

DB ||= Lux::Db::MainProxy.new
