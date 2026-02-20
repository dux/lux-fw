require 'spec_helper'

describe Lux::Current do
  before do
    Lux::Current.new('http://test.example.com/foo?bar=1')
  end

  describe '#initialize' do
    it 'sets up request, response, session, nav, and params' do
      current = Lux.current
      expect(current.request).to be_a(Rack::Request)
      expect(current.response).to be_a(Lux::Response)
      expect(current.session).to be_a(Lux::Current::Session)
      expect(current.nav).to be_a(Lux::Application::Nav)
      expect(current.params).to be_a(Hash)
    end

    it 'parses query string params' do
      expect(Lux.current.params[:bar]).to eq('1')
    end

    it 'stores itself in Thread.current[:lux]' do
      expect(Thread.current[:lux]).to eq(Lux.current)
    end
  end

  describe '#host' do
    it 'returns full host with scheme' do
      expect(Lux.current.host).to match(%r{https?://test\.example\.com})
    end
  end

  describe '#cache' do
    it 'caches block result for same key within request' do
      call_count = 0
      result1 = Lux.current.cache(:test_key) { call_count += 1; 'value' }
      result2 = Lux.current.cache(:test_key) { call_count += 1; 'other' }

      expect(result1).to eq('value')
      expect(result2).to eq('value')
      expect(call_count).to eq(1)
    end

    it 'caches nil results' do
      call_count = 0
      Lux.current.cache(:nil_key) { call_count += 1; nil }
      Lux.current.cache(:nil_key) { call_count += 1; 'not nil' }

      expect(call_count).to eq(1)
    end

    it 'returns different values for different keys' do
      a = Lux.current.cache(:key_a) { 'a' }
      b = Lux.current.cache(:key_b) { 'b' }
      expect(a).to eq('a')
      expect(b).to eq('b')
    end
  end

  describe '#no_cache?' do
    it 'returns false by default' do
      expect(Lux.current.no_cache?).to be false
    end

    it 'returns false even with no-cache header when can_clear_cache is not set' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_CACHE_CONTROL' => 'no-cache')
      Lux::Current.new(env)
      expect(Lux.current.no_cache?).to be_falsey
    end

    it 'returns true when no-cache header and can_clear_cache are set' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_CACHE_CONTROL' => 'no-cache')
      Lux::Current.new(env)
      Lux.current.can_clear_cache = true
      expect(Lux.current.no_cache?).to be true
    end
  end

  describe '#once' do
    it 'returns true on first call' do
      expect(Lux.current.once(:action1)).to be true
    end

    it 'returns false on subsequent calls with same id' do
      Lux.current.once(:action1)
      expect(Lux.current.once(:action1)).to be false
    end

    it 'returns true for different ids' do
      Lux.current.once(:action1)
      expect(Lux.current.once(:action2)).to be true
    end

    it 'yields block on first call only' do
      call_count = 0
      Lux.current.once(:block_test) { call_count += 1 }
      Lux.current.once(:block_test) { call_count += 1 }
      expect(call_count).to eq(1)
    end
  end

  describe '#uid' do
    it 'generates incrementing unique IDs' do
      id1 = Lux.current.uid
      id2 = Lux.current.uid
      expect(id1).to match(/^uid_\d+_\d+$/)
      expect(id1).not_to eq(id2)
    end

    it 'returns numeric only with num_only flag' do
      num = Lux.current.uid(true)
      expect(num).to be_a(Integer)
    end

    it 'increments the counter' do
      n1 = Lux.current.uid(true)
      n2 = Lux.current.uid(true)
      expect(n2).to eq(n1 + 1)
    end
  end

  describe '#secure_token' do
    it 'generates a token based on IP' do
      token = Lux.current.secure_token
      expect(token).to be_a(String)
      expect(token).to match(/\A[0-9a-f]{40}\z/)
    end

    it 'validates a correct token' do
      token = Lux.current.secure_token
      expect(Lux.current.secure_token(token)).to be true
    end

    it 'rejects an incorrect token' do
      expect(Lux.current.secure_token('invalid')).to be false
    end
  end

  describe '#ip' do
    it 'returns an IP address' do
      expect(Lux.current.ip).to be_a(String)
      expect(Lux.current.ip).not_to be_empty
    end
  end

  describe '#encrypt / #decrypt' do
    it 'encrypts and decrypts data with IP-based password' do
      encrypted = Lux.current.encrypt('secret')
      expect(encrypted).to be_a(String)
      expect(Lux.current.decrypt(encrypted)).to eq('secret')
    end
  end

  describe '#var' do
    it 'provides request-scoped variable storage' do
      Lux.current[:custom_var] = 'hello'
      expect(Lux.current[:custom_var]).to eq('hello')
    end
  end

  describe '#robot?' do
    it 'returns false for normal requests' do
      expect(Lux.current.robot?).to be false
    end

    it 'detects wget user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Wget/1.21')
      Lux::Current.new(env)
      expect(Lux.current.robot?).to be true
    end

    it 'detects curl user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'curl/7.79.1')
      Lux::Current.new(env)
      expect(Lux.current.robot?).to be true
    end
  end

  describe '#mobile?' do
    it 'returns false for desktop user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh)')
      Lux::Current.new(env)
      expect(Lux.current.mobile?).to be false
    end

    it 'detects iPhone user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS)')
      Lux::Current.new(env)
      expect(Lux.current.mobile?).to be true
    end

    it 'detects Android user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Linux; Android 12)')
      Lux::Current.new(env)
      expect(Lux.current.mobile?).to be true
    end
  end

  describe '#files_in_use' do
    it 'tracks files and returns false on first use' do
      result = Lux.current.files_in_use('app/models/user.rb')
      expect(result).to be false
    end

    it 'returns true for already-tracked files' do
      Lux.current.files_in_use('app/models/user.rb')
      result = Lux.current.files_in_use('app/models/user.rb')
      expect(result).to be true
    end

    it 'returns the set when called without args' do
      Lux.current.files_in_use('app/models/user.rb')
      expect(Lux.current.files_in_use).to be_a(Set)
      expect(Lux.current.files_in_use).to include('app/models/user.rb')
    end
  end
end
