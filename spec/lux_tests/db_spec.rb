require 'test_helper'
require 'sqlite3'

describe 'Lux::Db' do
  before do
    Lux::Db::CONNECTIONS.clear
    Lux.config[:db] = nil
    Lux.config[:db_url] = nil
    Lux.config[:db_config] = nil
    %w[DB_MAIN DB_LOG].each { |k| ENV.delete(k) }
  end

  describe '.configured_names' do
    it 'returns empty when no db configured' do
      _(Lux::Db.configured_names).must_equal []
    end

    it 'returns [:main] for string config' do
      Lux.config[:db] = 'sqlite://test.db'
      _(Lux::Db.configured_names).must_equal [:main]
    end

    it 'returns all names for hash config' do
      Lux.config[:db] = { 'main' => 'sqlite://a.db', 'log' => 'sqlite://b.db' }
      _(Lux::Db.configured_names.sort).must_equal [:log, :main]
    end
  end

  describe '.url_for' do
    it 'resolves from config hash' do
      Lux.config[:db] = { 'main' => 'sqlite://from_config.db' }
      _(Lux::Db.url_for(:main)).must_equal 'sqlite://from_config.db'
    end

    it 'resolves from config string' do
      Lux.config[:db] = 'sqlite://string_config.db'
      _(Lux::Db.url_for(:main)).must_equal 'sqlite://string_config.db'
    end

    it 'resolves named db from config hash' do
      Lux.config[:db] = { 'main' => 'sqlite://m.db', 'log' => 'sqlite://l.db' }
      _(Lux::Db.url_for(:log)).must_equal 'sqlite://l.db'
    end

    it 'ENV overrides config' do
      Lux.config[:db] = { 'main' => 'sqlite://config.db' }
      ENV['DB_MAIN'] = 'sqlite://env.db'
      _(Lux::Db.url_for(:main)).must_equal 'sqlite://env.db'
    end

    it 'legacy db_url config fallback for :main' do
      Lux.config[:db_url] = 'sqlite://legacy.db'
      _(Lux::Db.url_for(:main)).must_equal 'sqlite://legacy.db'
    end

    it 'returns nil when not configured' do
      _(Lux::Db.url_for(:missing)).must_be_nil
    end

    it 'ENV takes priority over all config' do
      Lux.config[:db] = { 'main' => 'sqlite://config.db' }
      Lux.config[:db_url] = 'sqlite://legacy.db'
      ENV['DB_MAIN'] = 'sqlite://env_main.db'
      _(Lux::Db.url_for(:main)).must_equal 'sqlite://env_main.db'
    end
  end

  describe '.connection' do
    it 'connects to sqlite and returns a Sequel::Database' do
      Lux.config[:db] = 'sqlite:/'
      db = Lux::Db.connection(:main)
      _(db).must_be_kind_of Sequel::Database
    end

    it 'caches connections' do
      Lux.config[:db] = 'sqlite:/'
      db1 = Lux::Db.connection(:main)
      db2 = Lux::Db.connection(:main)
      _(db1.object_id).must_equal db2.object_id
    end

    it 'raises for unconfigured database' do
      err = _{ Lux::Db.connection(:missing) }.must_raise Lux::Shell::Die
      _(err.message).must_match(/not configured/)
    end
  end

  describe '.connections' do
    it 'returns all active connections' do
      Lux.config[:db] = 'sqlite:/'
      Lux::Db.connection(:main)
      _(Lux::Db.connections.length).must_equal 1
      _(Lux::Db.connections.first).must_be_kind_of Sequel::Database
    end
  end

  describe '.disconnect_all' do
    it 'disconnects without error' do
      Lux.config[:db] = 'sqlite:/'
      Lux::Db.connection(:main)
      Lux::Db.disconnect_all
    end
  end

  describe 'string vs hash config equivalence' do
    it 'string config behaves same as hash with main key' do
      Lux.config[:db] = 'sqlite://test.db'
      string_url = Lux::Db.url_for(:main)
      string_names = Lux::Db.configured_names

      Lux.config[:db] = { 'main' => 'sqlite://test.db' }
      hash_url = Lux::Db.url_for(:main)
      hash_names = Lux::Db.configured_names

      _(string_url).must_equal hash_url
      _(string_names).must_equal hash_names
    end
  end

  describe 'multiple databases' do
    it 'manages separate connections per name' do
      Lux.config[:db] = { 'main' => 'sqlite:/', 'log' => 'sqlite:/' }
      main_db = Lux::Db.connection(:main)
      log_db = Lux::Db.connection(:log)
      refute_equal main_db.object_id, log_db.object_id
      _(Lux::Db.connections.length).must_equal 2
    end
  end

  describe 'MainProxy' do
    it 'delegates method calls to Lux.db(:main)' do
      Lux.config[:db] = 'sqlite:/'
      Lux::Db.connection(:main)
      proxy = Lux::Db::MainProxy.new
      _(proxy.tables).must_be_kind_of Array
    end

    it 'reports class as Sequel::Database' do
      proxy = Lux::Db::MainProxy.new
      _(proxy.class).must_equal Sequel::Database
    end
  end
end
