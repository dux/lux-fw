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
        unless url
          Lux.shell.die [
            "DB :#{name} not configured",
            "env: set DB_#{name.to_s.upcase}=postgres://localhost/dbname",
            "yaml: db.#{name}: postgres://localhost/dbname"
          ]
        end
        begin
          connect(url)
        rescue Sequel::DatabaseConnectionError => e
          if Lux.runtime.rake?
            connect(url.sub(/\/[^\/]+$/, '/postgres'))
          else
            die_connect_error(name, url, e)
          end
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
          Lux.shell.info "DB :#{name} connected (#{CONNECTIONS[name].opts[:database]})"
        rescue Sequel::DatabaseConnectionError => e
          next if Lux.runtime.rake?
          die_connect_error(name, url, e)
        end
      end
    end

    private

    # print clean DB connection failure and exit 1, no stack dump
    def die_connect_error(name, url, error)
      msg = error.message.to_s.lines.first.to_s.strip
      Lux.shell.die [
        "DB_#{name.to_s.upcase} connection failed",
        "url: #{redact_url(url)}",
        ("err: #{msg}" unless msg.empty?)
      ].compact
    end

    def redact_url(url)
      url.to_s.sub(%r{://([^:/@]+):([^@]+)@}, '://\1:***@')
    end

    def dbs_config
      val = Lux.config[:db]
      return {} unless val
      return { 'main' => val } if val.is_a?(String)
      val
    end

    def connect(url)
      config = DEFAULT_CONFIG.dup
      config.merge!(Lux.config[:db_config]) if Lux.config[:db_config].is_hash?

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

      return if Lux.shell.exec('psql', '-tAc',
        "SELECT 1 FROM pg_database WHERE datname = '#{test_db.gsub("'", "''")}'") == '1'

      Lux.shell.info "DB create: %s (schema from %s)" % [test_db, source_db]
      Lux.shell 'createdb', test_db
      # shell mode for pipe + redirect; values are shellescaped.
      Lux.shell 'pg_dump --schema-only --no-owner --no-privileges %s | psql -q %s > /dev/null 2>&1' %
        [source_db.shellescape, test_db.shellescape], shell: true
    end
  end
end

DB ||= Lux::Db::MainProxy.new
