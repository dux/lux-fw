require 'spec_helper'
require 'sqlite3'

describe 'Lux::Db' do
  before(:each) do
    Lux::Db::CONNECTIONS.clear
    Lux.config[:db] = nil
    Lux.config[:db_url] = nil
    Lux.config[:db_config] = nil
    %w[DB_MAIN DB_LOG DB_URL].each { |k| ENV.delete(k) }
  end

  describe '.configured_names' do
    it 'returns empty when no db configured' do
      expect(Lux::Db.configured_names).to eq([])
    end

    it 'returns [:main] for string config' do
      Lux.config[:db] = 'sqlite://test.db'
      expect(Lux::Db.configured_names).to eq([:main])
    end

    it 'returns all names for hash config' do
      Lux.config[:db] = { 'main' => 'sqlite://a.db', 'log' => 'sqlite://b.db' }
      expect(Lux::Db.configured_names).to contain_exactly(:main, :log)
    end
  end

  describe '.url_for' do
    it 'resolves from config hash' do
      Lux.config[:db] = { 'main' => 'sqlite://from_config.db' }
      expect(Lux::Db.url_for(:main)).to eq('sqlite://from_config.db')
    end

    it 'resolves from config string' do
      Lux.config[:db] = 'sqlite://string_config.db'
      expect(Lux::Db.url_for(:main)).to eq('sqlite://string_config.db')
    end

    it 'resolves named db from config hash' do
      Lux.config[:db] = { 'main' => 'sqlite://m.db', 'log' => 'sqlite://l.db' }
      expect(Lux::Db.url_for(:log)).to eq('sqlite://l.db')
    end

    it 'ENV overrides config' do
      Lux.config[:db] = { 'main' => 'sqlite://config.db' }
      ENV['DB_MAIN'] = 'sqlite://env.db'
      expect(Lux::Db.url_for(:main)).to eq('sqlite://env.db')
    end

    it 'DB_URL fallback for :main' do
      ENV['DB_URL'] = 'sqlite://fallback.db'
      expect(Lux::Db.url_for(:main)).to eq('sqlite://fallback.db')
    end

    it 'DB_URL does not apply to non-main' do
      ENV['DB_URL'] = 'sqlite://fallback.db'
      expect(Lux::Db.url_for(:log)).to be_nil
    end

    it 'legacy db_url config fallback for :main' do
      Lux.config[:db_url] = 'sqlite://legacy.db'
      expect(Lux::Db.url_for(:main)).to eq('sqlite://legacy.db')
    end

    it 'returns nil when not configured' do
      expect(Lux::Db.url_for(:missing)).to be_nil
    end

    it 'ENV takes priority over all config' do
      Lux.config[:db] = { 'main' => 'sqlite://config.db' }
      Lux.config[:db_url] = 'sqlite://legacy.db'
      ENV['DB_URL'] = 'sqlite://db_url.db'
      ENV['DB_MAIN'] = 'sqlite://env_main.db'
      expect(Lux::Db.url_for(:main)).to eq('sqlite://env_main.db')
    end
  end

  describe '.connection' do
    it 'connects to sqlite and returns a Sequel::Database' do
      Lux.config[:db] = 'sqlite:/'
      db = Lux::Db.connection(:main)
      expect(db).to be_a(Sequel::Database)
    end

    it 'caches connections' do
      Lux.config[:db] = 'sqlite:/'
      db1 = Lux::Db.connection(:main)
      db2 = Lux::Db.connection(:main)
      expect(db1.object_id).to eq(db2.object_id)
    end

    it 'raises for unconfigured database' do
      expect { Lux::Db.connection(:missing) }.to raise_error(RuntimeError, /not configured/)
    end
  end

  describe '.connections' do
    it 'returns all active connections' do
      Lux.config[:db] = 'sqlite:/'
      Lux::Db.connection(:main)
      expect(Lux::Db.connections.length).to eq(1)
      expect(Lux::Db.connections.first).to be_a(Sequel::Database)
    end
  end

  describe '.disconnect_all' do
    it 'disconnects without error' do
      Lux.config[:db] = 'sqlite:/'
      Lux::Db.connection(:main)
      expect { Lux::Db.disconnect_all }.not_to raise_error
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

      expect(string_url).to eq(hash_url)
      expect(string_names).to eq(hash_names)
    end
  end

  describe 'multiple databases' do
    it 'manages separate connections per name' do
      Lux.config[:db] = { 'main' => 'sqlite:/', 'log' => 'sqlite:/' }
      main_db = Lux::Db.connection(:main)
      log_db = Lux::Db.connection(:log)
      expect(main_db.object_id).not_to eq(log_db.object_id)
      expect(Lux::Db.connections.length).to eq(2)
    end
  end

  describe 'MainProxy' do
    it 'delegates method calls to Lux.db(:main)' do
      Lux.config[:db] = 'sqlite:/'
      Lux::Db.connection(:main)
      proxy = Lux::Db::MainProxy.new
      expect(proxy.tables).to be_an(Array)
    end

    it 'reports class as Sequel::Database' do
      proxy = Lux::Db::MainProxy.new
      expect(proxy.class).to eq(Sequel::Database)
    end
  end
end
