require 'uri'
require 'monitor'
require 'sequel/connection_pool/threaded'

module Lux
  module Db
    extend self

    CONNECTIONS ||= {}
    # reentrant: connect may touch Lux.db again while the first connect runs
    CONNECTIONS_LOCK ||= Monitor.new

    # loggers attached to every connection on connect (populated by ext/logger).
    # connections are lazy, so we cannot attach at plugin-load time.
    CONNECTION_LOGGERS ||= []

    DEFAULT_CONFIG ||= {
      max_connections: 5,
      pool_timeout: 5,
      encoding: 'utf8',
      sslmode: 'disable',
    }.freeze

    # fibered servers run hundreds of concurrent requests per process, not a
    # small thread pool - widen the default; db_config still overrides
    FIBER_MAX_CONNECTIONS ||= 25

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
      CONNECTIONS[name] || CONNECTIONS_LOCK.synchronize { connect_once(name) }
    end

    def connect_once(name)
      CONNECTIONS[name] ||= begin
        url = url_for(name)
        unless url
          Lux.shell.die [
            "DB :#{name} not configured",
            "env: set DB_#{name.to_s.upcase}=postgres://localhost/dbname",
            "yaml: db.#{name}: postgres://localhost/dbname"
          ]
        end
        url = resolve_test_url(name, url)
        begin
          connect(url)
        rescue Sequel::DatabaseConnectionError => e
          die_connect_error(name, url, e)
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
        next unless url_for(name)
        db = connection(name)
        Lux.shell.info "DB :#{name} connected (#{db.opts[:database]})"
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
      # an explicit ?sslmode= in the URL wins over the default
      config.delete(:sslmode) if URI.parse(url).query.to_s.match?(/(?:\A|&)sslmode=/)

      if Lux.env.fibers?
        # key connections by fiber, or every fiber on the reactor thread
        # would share (and interleave queries on) one PG connection
        Sequel.extension :fiber_concurrency
        config[:max_connections] = FIBER_MAX_CONNECTIONS
      end

      config.merge!(Lux.config[:db_config]) if Lux.config[:db_config].is_hash?

      db = Sequel.connect(url, config)

      if db.adapter_scheme == :postgres
        db.extension :pg_array, :pg_json
      end

      CONNECTION_LOGGERS.each { |l| db.loggers << l }

      db
    end

    def test_db_url(url)
      url.sub(%r{/([^/?]+)(?=\?|\z)}) { "/#{$1}_test" }
    end

    # In test env, point a connection at its <db>_test sibling and ensure that
    # sibling exists. Shared by the lazy `connection` path and the eager `boot!`
    # path so both resolve the same database - otherwise a model that connects
    # lazily (e.g. a factory insert before the first request) binds to the
    # non-test DB while boot! would have used <db>_test.
    #
    # CLI tasks are excluded: db:test:am and friends manage the _test
    # database itself (drop/create/migrate), so they must operate on the literal
    # configured DB and never hold an open connection into _test.
    def resolve_test_url(name, url)
      return url unless Lux.env.test?
      return url if Lux.runtime.task_runner?
      return url unless url.to_s.start_with?('postgres')

      test_url = test_db_url(url)
      ensure_test_db(test_url)
      test_url
    end

    def db_name_from_url(url)
      URI.parse(url).path.sub('/', '')
    end

    def ensure_test_db(test_url)
      test_db    = db_name_from_url(test_url)
      source_url = test_url.sub(%r{_test(?=\?|\z)}, '')
      admin_url  = test_url.sub(%r{/[^/?]+(?=\?|\z)}, '/postgres')

      return if Lux.shell.exec('psql', admin_url, '-tAc',
        "SELECT 1 FROM pg_database WHERE datname = '#{test_db.gsub("'", "''")}'") == '1'

      Lux.shell.info 'DB create: %s (schema from %s)' % [test_db, db_name_from_url(source_url)]
      Lux.shell 'psql', admin_url, '-c', %[CREATE DATABASE "#{test_db.gsub('"', '""')}"]
      # shell mode for pipe + redirect; values are shellescaped.
      Lux.shell 'pg_dump --schema-only --no-owner --no-privileges %s | psql -q %s > /dev/null 2>&1' %
        [source_url.shellescape, test_url.shellescape], shell: true
    end
  end
end

DB ||= Lux::Db::MainProxy.new
