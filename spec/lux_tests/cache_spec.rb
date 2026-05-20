require 'spec_helper'

describe Lux::Cache do
  before do
    Lux::Current.new('http://test-cache')
  end

  let(:cache) { Lux::Cache.new(:memory) }

  after do
    cache.clear
  end

  describe '#server=' do
    it 'initializes with memory server by default' do
      c = Lux::Cache.new
      expect(c.server).to be_a(Lux::Cache::MemoryServer)
    end

    it 'accepts :memory symbol' do
      c = Lux::Cache.new(:memory)
      expect(c.server).to be_a(Lux::Cache::MemoryServer)
    end
  end

  describe '#write / #read' do
    it 'writes and reads a value' do
      cache.write('key1', 'value1')
      expect(cache.read('key1')).to eq('value1')
    end

    it 'returns nil for missing keys' do
      expect(cache.read('nonexistent')).to be_nil
    end

    it 'overwrites existing values' do
      cache.write('key1', 'old')
      cache.write('key1', 'new')
      expect(cache.read('key1')).to eq('new')
    end
  end

  describe '#delete' do
    it 'removes a cached value' do
      cache.write('key1', 'value1')
      cache.delete('key1')
      expect(cache.read('key1')).to be_nil
    end
  end

  describe '#clear' do
    it 'removes all cached values' do
      cache.write('a', 1)
      cache.write('b', 2)
      cache.clear
      expect(cache.read('a')).to be_nil
      expect(cache.read('b')).to be_nil
    end
  end

  describe '#[] and #[]=' do
    it 'provides hash-like access' do
      cache['mykey'] = 'myval'
      expect(cache['mykey']).to eq('myval')
    end
  end

  describe '#is_available?' do
    it 'returns true for working cache server' do
      expect(cache.is_available?).to be true
    end
  end

  describe '#generate_key' do
    it 'returns string keys unchanged' do
      expect(cache.generate_key('my-key')).to eq('my-key')
    end

    it 'generates SHA1 key for non-string data' do
      key = cache.generate_key(123)
      expect(key).to match(/\A[0-9a-f]{40}\z/)
    end

    it 'generates consistent keys for same input' do
      key1 = cache.generate_key(:test, 123)
      key2 = cache.generate_key(:test, 123)
      expect(key1).to eq(key2)
    end

    it 'generates different keys for different input' do
      key1 = cache.generate_key(:a, 1)
      key2 = cache.generate_key(:b, 2)
      expect(key1).not_to eq(key2)
    end
  end

  describe '#fetch' do
    it 'returns the original value (not a Marshal blob)' do
      result = cache.fetch('k') { { a: 1 } }
      expect(result).to eq({ a: 1 })
    end

    it 'caches and yields only once per key' do
      calls = 0
      2.times { cache.fetch('k') { calls += 1; 'v' } }
      expect(calls).to eq(1)
    end

    it 'returns value written via #write (no Marshal mismatch)' do
      cache.write('k', { foo: 1 })
      result = cache.fetch('k') { { foo: 999 } }
      expect(result).to eq({ foo: 1 })
    end

    it 'force: true bypasses cache and recomputes' do
      cache.write('k', 'old')
      result = cache.fetch('k', force: true) { 'new' }
      expect(result).to eq('new')
      expect(cache.read('k')).to eq('new')
    end

    it 'if: false skips caching entirely' do
      calls = 0
      2.times { cache.fetch('k', if: false) { calls += 1; 'v' } }
      expect(calls).to eq(2)
      expect(cache.read('k')).to be_nil
    end

    it 'delete_if_empty: true drops cached empty result' do
      cache.fetch('k', delete_if_empty: true) { [] }
      expect(cache.read('k')).to be_nil
    end

    it 'delete_if_empty: true keeps non-empty result' do
      cache.fetch('k', delete_if_empty: true) { [1, 2] }
      expect(cache.read('k')).to eq([1, 2])
    end

    it 'accepts a bare integer as ttl shortcut' do
      cache.fetch('k', 60) { 'v' }
      expect(cache.read('k')).to eq('v')
    end
  end

  describe '#lock' do
    it 'yields the block' do
      result = cache.lock('k', 60) { 42 }
      expect(result).to eq(42)
    end

    it 'refreshes the lock key on every call' do
      cache.lock('k', 0.05) { :first }
      first_ts = cache.server.get('syslock-k')
      sleep 0.1
      cache.lock('k', 0.05) { :second }
      second_ts = cache.server.get('syslock-k')
      expect(second_ts).to be > first_ts
    end
  end

  describe 'log_get side effects' do
    it 'does not mutate global Lux.config[:show_cache_log]' do
      Lux.config[:show_cache_log] = nil
      cache.write('k', 'v')
      cache.read('k')
      expect(Lux.config[:show_cache_log]).to be_nil
    end
  end
end

describe Lux::Cache::MemoryServer do
  let(:server) { Lux::Cache::MemoryServer.new }

  after { server.clear }

  describe 'instance isolation' do
    it 'two instances do not share state' do
      a = Lux::Cache::MemoryServer.new
      b = Lux::Cache::MemoryServer.new
      a.set('k', 'A')
      expect(b.get('k')).to be_nil
    end
  end

  describe '#set / #get' do
    it 'stores and retrieves values' do
      server.set('k', 'v')
      expect(server.get('k')).to eq('v')
    end

    it 'returns nil for missing keys' do
      expect(server.get('missing')).to be_nil
    end
  end

  describe 'TTL expiration' do
    it 'returns nil for expired keys' do
      server.set('k', 'v', -1) # TTL in the past
      sleep 0.01
      expect(server.get('k')).to be_nil
    end

    it 'returns value for non-expired keys' do
      server.set('k', 'v', 60)
      expect(server.get('k')).to eq('v')
    end
  end

  describe '#fetch' do
    it 'returns cached value if present' do
      server.set('k', 'cached')
      result = server.fetch('k') { 'computed' }
      expect(result).to eq('cached')
    end

    it 'computes and caches if missing' do
      result = server.fetch('new_key') { 'computed' }
      expect(result).to eq('computed')
      expect(server.get('new_key')).to eq('computed')
    end
  end

  describe '#delete' do
    it 'removes a key and returns true' do
      server.set('k', 'v')
      expect(server.delete('k')).to be true
    end

    it 'returns false for missing key' do
      expect(server.delete('missing')).to be false
    end
  end

  describe '#get_multi' do
    it 'returns multiple values' do
      server.set('a', 1)
      server.set('b', 2)
      server.set('c', 3)
      result = server.get_multi('a', 'c')
      expect(result).to eq({ 'a' => 1, 'c' => 3 })
    end
  end
end

describe Lux::Cache::NullServer do
  let(:server) { Lux::Cache::NullServer.new }

  it 'never caches - get always returns nil' do
    server.set('k', 'v')
    expect(server.get('k')).to be_nil
  end

  it 'fetch always yields' do
    call_count = 0
    3.times { server.fetch('k') { call_count += 1; 'v' } }
    expect(call_count).to eq(3)
  end

  it 'get_multi returns empty hash' do
    expect(server.get_multi('a', 'b')).to eq({})
  end

  it 'clear returns true' do
    expect(server.clear).to be true
  end
end

describe Lux::Cache::SqliteServer do
  require 'lux/cache/lib/sqlite_server'

  let(:tmpfile) { Pathname.new("./tmp/cache_spec_#{Process.pid}.sqlite") }
  let(:server)  { Lux::Cache::SqliteServer.new(tmpfile.to_s) }

  before { tmpfile.delete if tmpfile.exist? }
  after  do
    server.clear rescue nil
    tmpfile.delete if tmpfile.exist?
    Pathname.new(tmpfile.to_s + '-wal').delete rescue nil
    Pathname.new(tmpfile.to_s + '-shm').delete rescue nil
  end

  it 'sets and gets values' do
    server.set('k', { a: 1 })
    expect(server.get('k')).to eq({ a: 1 })
  end

  it 'upserts on duplicate key' do
    server.set('k', 'old')
    server.set('k', 'new')
    expect(server.get('k')).to eq('new')
  end

  it 'returns nil for missing keys' do
    expect(server.get('missing')).to be_nil
  end

  it 'expires entries with past valid_to' do
    server.set('k', 'v', -1)
    expect(server.get('k')).to be_nil
  end

  it 'fetch returns existing value' do
    server.set('k', 'cached')
    expect(server.fetch('k') { 'computed' }).to eq('cached')
  end

  it 'fetch computes and stores if missing' do
    expect(server.fetch('k') { 'computed' }).to eq('computed')
    expect(server.get('k')).to eq('computed')
  end

  it 'get_multi returns hash of values for known keys' do
    server.set('a', 1)
    server.set('b', 2)
    expect(server.get_multi('a', 'b')).to eq({ 'a' => 1, 'b' => 2 })
  end

  it 'falls back to default path when nil given' do
    default = Pathname.new('./tmp/lux_cache.sqlite')
    existed = default.exist?
    s = Lux::Cache::SqliteServer.new(nil)
    expect(default.exist?).to be true
    s.clear
  ensure
    unless existed
      default.delete if default.exist?
      Pathname.new('./tmp/lux_cache.sqlite-wal').delete rescue nil
      Pathname.new('./tmp/lux_cache.sqlite-shm').delete rescue nil
    end
  end
end
