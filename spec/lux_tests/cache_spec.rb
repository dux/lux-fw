require 'test_helper'

describe Lux::Cache do
  before do
    Lux::Current.new('http://test-cache')
  end

  def cache
    @cache ||= Lux::Cache.new(:memory)
  end

  after do
    cache.clear
  end

  describe '#server=' do
    it 'initializes with memory server by default' do
      c = Lux::Cache.new
      _(c.server).must_be_kind_of Lux::Cache::MemoryServer
    end

    it 'accepts :memory symbol' do
      c = Lux::Cache.new(:memory)
      _(c.server).must_be_kind_of Lux::Cache::MemoryServer
    end
  end

  describe '#write / #read' do
    it 'writes and reads a value' do
      cache.write('key1', 'value1')
      _(cache.read('key1')).must_equal 'value1'
    end

    it 'returns nil for missing keys' do
      _(cache.read('nonexistent')).must_be_nil
    end

    it 'overwrites existing values' do
      cache.write('key1', 'old')
      cache.write('key1', 'new')
      _(cache.read('key1')).must_equal 'new'
    end
  end

  describe '#delete' do
    it 'removes a cached value' do
      cache.write('key1', 'value1')
      cache.delete('key1')
      _(cache.read('key1')).must_be_nil
    end
  end

  describe '#clear' do
    it 'removes all cached values' do
      cache.write('a', 1)
      cache.write('b', 2)
      cache.clear
      _(cache.read('a')).must_be_nil
      _(cache.read('b')).must_be_nil
    end
  end

  describe '#[] and #[]=' do
    it 'provides hash-like access' do
      cache['mykey'] = 'myval'
      _(cache['mykey']).must_equal 'myval'
    end
  end

  describe '#is_available?' do
    it 'returns true for working cache server' do
      _(cache.is_available?).must_equal true
    end
  end

  describe '#generate_key' do
    it 'returns string keys unchanged' do
      _(cache.generate_key('my-key')).must_equal 'my-key'
    end

    it 'generates SHA1 key for non-string data' do
      key = cache.generate_key(123)
      _(key).must_match(/\A[0-9a-f]{40}\z/)
    end

    it 'generates consistent keys for same input' do
      key1 = cache.generate_key(:test, 123)
      key2 = cache.generate_key(:test, 123)
      _(key1).must_equal key2
    end

    it 'generates different keys for different input' do
      key1 = cache.generate_key(:a, 1)
      key2 = cache.generate_key(:b, 2)
      _(key1).wont_equal key2
    end
  end

  describe '#fetch' do
    it 'returns the original value (not a Marshal blob)' do
      result = cache.fetch('k') { { a: 1 } }
      _(result).must_equal({ a: 1 })
    end

    it 'caches and yields only once per key' do
      calls = 0
      2.times { cache.fetch('k') { calls += 1; 'v' } }
      _(calls).must_equal 1
    end

    it 'returns value written via #write (no Marshal mismatch)' do
      cache.write('k', { foo: 1 })
      result = cache.fetch('k') { { foo: 999 } }
      _(result).must_equal({ foo: 1 })
    end

    it 'force: true bypasses cache and recomputes' do
      cache.write('k', 'old')
      result = cache.fetch('k', force: true) { 'new' }
      _(result).must_equal 'new'
      _(cache.read('k')).must_equal 'new'
    end

    it 'if: false skips caching entirely' do
      calls = 0
      2.times { cache.fetch('k', if: false) { calls += 1; 'v' } }
      _(calls).must_equal 2
      _(cache.read('k')).must_be_nil
    end

    it 'delete_if_empty: true drops cached empty result' do
      cache.fetch('k', delete_if_empty: true) { [] }
      _(cache.read('k')).must_be_nil
    end

    it 'delete_if_empty: true keeps non-empty result' do
      cache.fetch('k', delete_if_empty: true) { [1, 2] }
      _(cache.read('k')).must_equal [1, 2]
    end

    it 'accepts a bare integer as ttl shortcut' do
      cache.fetch('k', 60) { 'v' }
      _(cache.read('k')).must_equal 'v'
    end
  end

  describe '#lock' do
    it 'yields the block' do
      result = cache.lock('k', 60) { 42 }
      _(result).must_equal 42
    end

    it 'refreshes the lock key on every call' do
      cache.lock('k', 0.05) { :first }
      first_ts = cache.server.get('syslock-k')
      sleep 0.1
      cache.lock('k', 0.05) { :second }
      second_ts = cache.server.get('syslock-k')
      assert second_ts > first_ts
    end
  end

  describe 'log_get side effects' do
    it 'does not mutate global Lux.config[:show_cache_log]' do
      Lux.config[:show_cache_log] = nil
      cache.write('k', 'v')
      cache.read('k')
      _(Lux.config[:show_cache_log]).must_be_nil
    end
  end
end

describe Lux::Cache::MemoryServer do
  def server
    @server ||= Lux::Cache::MemoryServer.new
  end

  after { server.clear }

  describe 'instance isolation' do
    it 'two instances do not share state' do
      a = Lux::Cache::MemoryServer.new
      b = Lux::Cache::MemoryServer.new
      a.set('k', 'A')
      _(b.get('k')).must_be_nil
    end
  end

  describe '#set / #get' do
    it 'stores and retrieves values' do
      server.set('k', 'v')
      _(server.get('k')).must_equal 'v'
    end

    it 'returns nil for missing keys' do
      _(server.get('missing')).must_be_nil
    end
  end

  describe 'TTL expiration' do
    it 'returns nil for expired keys' do
      server.set('k', 'v', -1) # TTL in the past
      sleep 0.01
      _(server.get('k')).must_be_nil
    end

    it 'returns value for non-expired keys' do
      server.set('k', 'v', 60)
      _(server.get('k')).must_equal 'v'
    end
  end

  describe '#fetch' do
    it 'returns cached value if present' do
      server.set('k', 'cached')
      result = server.fetch('k') { 'computed' }
      _(result).must_equal 'cached'
    end

    it 'computes and caches if missing' do
      result = server.fetch('new_key') { 'computed' }
      _(result).must_equal 'computed'
      _(server.get('new_key')).must_equal 'computed'
    end
  end

  describe '#delete' do
    it 'removes a key and returns true' do
      server.set('k', 'v')
      _(server.delete('k')).must_equal true
    end

    it 'returns false for missing key' do
      _(server.delete('missing')).must_equal false
    end
  end

  describe '#get_multi' do
    it 'returns multiple values' do
      server.set('a', 1)
      server.set('b', 2)
      server.set('c', 3)
      result = server.get_multi('a', 'c')
      _(result).must_equal({ 'a' => 1, 'c' => 3 })
    end
  end
end

describe Lux::Cache::NullServer do
  def server
    @server ||= Lux::Cache::NullServer.new
  end

  it 'never caches - get always returns nil' do
    server.set('k', 'v')
    _(server.get('k')).must_be_nil
  end

  it 'fetch always yields' do
    call_count = 0
    3.times { server.fetch('k') { call_count += 1; 'v' } }
    _(call_count).must_equal 3
  end

  it 'get_multi returns empty hash' do
    _(server.get_multi('a', 'b')).must_equal({})
  end

  it 'clear returns true' do
    _(server.clear).must_equal true
  end
end

describe Lux::Cache::SqliteServer do
  require 'lux/cache/lib/sqlite_server'

  def tmpfile
    @tmpfile ||= Pathname.new("./tmp/cache_spec_#{Process.pid}.sqlite")
  end

  def server
    @server ||= Lux::Cache::SqliteServer.new(tmpfile.to_s)
  end

  before { tmpfile.delete if tmpfile.exist? }
  after  do
    server.clear rescue nil
    tmpfile.delete if tmpfile.exist?
    Pathname.new(tmpfile.to_s + '-wal').delete rescue nil
    Pathname.new(tmpfile.to_s + '-shm').delete rescue nil
  end

  it 'sets and gets values' do
    server.set('k', { a: 1 })
    _(server.get('k')).must_equal({ a: 1 })
  end

  it 'upserts on duplicate key' do
    server.set('k', 'old')
    server.set('k', 'new')
    _(server.get('k')).must_equal 'new'
  end

  it 'returns nil for missing keys' do
    _(server.get('missing')).must_be_nil
  end

  it 'expires entries with past valid_to' do
    server.set('k', 'v', -1)
    _(server.get('k')).must_be_nil
  end

  it 'fetch returns existing value' do
    server.set('k', 'cached')
    _(server.fetch('k') { 'computed' }).must_equal 'cached'
  end

  it 'fetch computes and stores if missing' do
    _(server.fetch('k') { 'computed' }).must_equal 'computed'
    _(server.get('k')).must_equal 'computed'
  end

  it 'get_multi returns hash of values for known keys' do
    server.set('a', 1)
    server.set('b', 2)
    _(server.get_multi('a', 'b')).must_equal({ 'a' => 1, 'b' => 2 })
  end

  it 'falls back to default path when nil given' do
    default = Pathname.new('./tmp/lux_cache.sqlite')
    existed = default.exist?
    s = Lux::Cache::SqliteServer.new(nil)
    _(default.exist?).must_equal true
    s.clear
  ensure
    unless existed
      default.delete if default.exist?
      Pathname.new('./tmp/lux_cache.sqlite-wal').delete rescue nil
      Pathname.new('./tmp/lux_cache.sqlite-shm').delete rescue nil
    end
  end
end
