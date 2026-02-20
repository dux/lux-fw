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
end

describe Lux::Cache::MemoryServer do
  let(:server) { Lux::Cache::MemoryServer.new }

  after { server.clear }

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
