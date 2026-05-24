require 'test_helper'

describe Lux::Current do
  before do
    Lux::Current.new('http://test.example.com/foo?bar=1')
  end

  describe '#initialize' do
    it 'sets up request, response, session, nav, and params' do
      current = Lux.current
      _(current.request).must_be_kind_of Rack::Request
      _(current.response).must_be_kind_of Lux::Response
      _(current.session).must_be_kind_of Lux::Current::Session
      _(current.nav).must_be_kind_of Lux::Application::Nav
      _(current.params).must_be_kind_of Hash
    end

    it 'parses query string params' do
      _(Lux.current.params[:bar]).must_equal '1'
    end

    it 'stores itself in Thread.current[:lux]' do
      _(Thread.current[:lux]).must_equal Lux.current
    end
  end

  describe '#host' do
    it 'returns full host with scheme' do
      _(Lux.current.host).must_match(%r{https?://test\.example\.com})
    end
  end

  describe '#cache' do
    it 'caches block result for same key within request' do
      call_count = 0
      result1 = Lux.current.cache(:test_key) { call_count += 1; 'value' }
      result2 = Lux.current.cache(:test_key) { call_count += 1; 'other' }

      _(result1).must_equal 'value'
      _(result2).must_equal 'value'
      _(call_count).must_equal 1
    end

    it 'caches nil results' do
      call_count = 0
      Lux.current.cache(:nil_key) { call_count += 1; nil }
      Lux.current.cache(:nil_key) { call_count += 1; 'not nil' }

      _(call_count).must_equal 1
    end

    it 'returns different values for different keys' do
      a = Lux.current.cache(:key_a) { 'a' }
      b = Lux.current.cache(:key_b) { 'b' }
      _(a).must_equal 'a'
      _(b).must_equal 'b'
    end
  end

  describe '#no_cache?' do
    it 'returns false by default' do
      _(Lux.current.no_cache?).must_equal false
    end

    it 'returns false even with no-cache header when can_clear_cache is not set' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_CACHE_CONTROL' => 'no-cache')
      Lux::Current.new(env)
      refute Lux.current.no_cache?
    end

    it 'returns true when no-cache header and can_clear_cache are set' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_CACHE_CONTROL' => 'no-cache')
      Lux::Current.new(env)
      Lux.current.can_clear_cache = true
      _(Lux.current.no_cache?).must_equal true
    end
  end

  describe '#once' do
    it 'returns true on first call' do
      _(Lux.current.once(:action1)).must_equal true
    end

    it 'returns false on subsequent calls with same id' do
      Lux.current.once(:action1)
      _(Lux.current.once(:action1)).must_equal false
    end

    it 'returns true for different ids' do
      Lux.current.once(:action1)
      _(Lux.current.once(:action2)).must_equal true
    end

    it 'yields block on first call only' do
      call_count = 0
      Lux.current.once(:block_test) { call_count += 1 }
      Lux.current.once(:block_test) { call_count += 1 }
      _(call_count).must_equal 1
    end
  end

  describe '#uid' do
    it 'generates incrementing unique IDs' do
      id1 = Lux.current.uid
      id2 = Lux.current.uid
      _(id1).must_match(/^uid_\d+_\d+$/)
      refute_equal id2, id1
    end

    it 'returns numeric only with num_only flag' do
      num = Lux.current.uid(true)
      _(num).must_be_kind_of Integer
    end

    it 'increments the counter' do
      n1 = Lux.current.uid(true)
      n2 = Lux.current.uid(true)
      _(n2).must_equal(n1 + 1)
    end
  end

  describe '#secure_token' do
    it 'generates a token based on IP' do
      token = Lux.current.secure_token
      _(token).must_be_kind_of String
      _(token).must_match(/\A[0-9a-f]{40}\z/)
    end

    it 'validates a correct token' do
      token = Lux.current.secure_token
      _(Lux.current.secure_token(token)).must_equal true
    end

    it 'rejects an incorrect token' do
      _(Lux.current.secure_token('invalid')).must_equal false
    end
  end

  describe '#ip' do
    it 'returns an IP address' do
      _(Lux.current.ip).must_be_kind_of String
      refute_empty Lux.current.ip
    end
  end

  describe '#encrypt / #decrypt' do
    it 'encrypts and decrypts data with IP-based password' do
      encrypted = Lux.current.encrypt('secret')
      _(encrypted).must_be_kind_of String
      _(Lux.current.decrypt(encrypted)).must_equal 'secret'
    end
  end

  describe '#var' do
    it 'provides request-scoped variable storage' do
      Lux.current[:custom_var] = 'hello'
      _(Lux.current[:custom_var]).must_equal 'hello'
    end
  end

  describe '#robot?' do
    it 'returns false for normal requests' do
      _(Lux.current.robot?).must_equal false
    end

    it 'detects wget user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Wget/1.21')
      Lux::Current.new(env)
      _(Lux.current.robot?).must_equal true
    end

    it 'detects curl user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'curl/7.79.1')
      Lux::Current.new(env)
      _(Lux.current.robot?).must_equal true
    end
  end

  describe '#mobile?' do
    it 'returns false for desktop user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh)')
      Lux::Current.new(env)
      _(Lux.current.mobile?).must_equal false
    end

    it 'detects iPhone user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS)')
      Lux::Current.new(env)
      _(Lux.current.mobile?).must_equal true
    end

    it 'detects Android user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Linux; Android 12)')
      Lux::Current.new(env)
      _(Lux.current.mobile?).must_equal true
    end
  end

  describe '#files_in_use' do
    it 'tracks files and returns false on first use' do
      result = Lux.current.files_in_use('app/models/user.rb')
      _(result).must_equal false
    end

    it 'returns true for already-tracked files' do
      Lux.current.files_in_use('app/models/user.rb')
      result = Lux.current.files_in_use('app/models/user.rb')
      _(result).must_equal true
    end

    it 'returns the set when called without args' do
      Lux.current.files_in_use('app/models/user.rb')
      _(Lux.current.files_in_use).must_be_kind_of Set
      _(Lux.current.files_in_use).must_include 'app/models/user.rb'
    end
  end
end
