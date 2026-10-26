require 'test_helper'

describe Lux::Context do
  before do
    Lux::Context.new('http://test.example.com/foo?bar=1')
  end

  describe '#initialize' do
    it 'sets up request, response, session, nav, and params' do
      current = Lux.ctx
      _(current.request).must_be_kind_of Rack::Request
      _(current.response).must_be_kind_of Lux::Response
      _(current.session).must_be_kind_of Lux::Context::Session
      _(current.nav).must_be_kind_of Lux::Router::Nav
      _(current.params).must_be_kind_of Hash
    end

    it 'parses query string params' do
      _(Lux.ctx.params[:bar]).must_equal '1'
    end

    it 'stores itself in Thread.current[:lux]' do
      _(Thread.current[:lux]).must_equal Lux.ctx
    end
  end

  describe 'outside a request' do
    before { Thread.current[:lux] = nil }

    it 'builds a context without request-bound parts' do
      ctx = Lux.ctx
      _(ctx.request).must_be_nil
      _(ctx.response).must_be_nil
      _(ctx.session).must_be_nil
      _(ctx.nav).must_be_nil
      _(ctx.params).must_be_nil
      _(ctx.no_cache?).must_equal false
    end

    it 'keeps the per-thread bag and memoize working' do
      Lux.ctx[:k] = 1
      _(Lux.ctx[:k]).must_equal 1
      _(Lux.ctx.cache(:x) { 2 }).must_equal 2
    end

    it 'snapshots without request fields' do
      snap = Lux.ctx.snapshot
      _(snap[:url]).must_be_nil
      _(snap[:ip]).must_be_nil
      refute_nil snap[:request_id]
    end

    it 'refuses to build a URL from a missing request' do
      _ { Lux.url }.must_raise NoMethodError
    end
  end

  describe '#host' do
    it 'returns full host with scheme' do
      _(Lux.ctx.host).must_match(%r{https?://test\.example\.com})
    end
  end

  describe '#cache' do
    it 'caches block result for same key within request' do
      call_count = 0
      result1 = Lux.ctx.cache(:test_key) { call_count += 1; 'value' }
      result2 = Lux.ctx.cache(:test_key) { call_count += 1; 'other' }

      _(result1).must_equal 'value'
      _(result2).must_equal 'value'
      _(call_count).must_equal 1
    end

    it 'caches nil results' do
      call_count = 0
      Lux.ctx.cache(:nil_key) { call_count += 1; nil }
      Lux.ctx.cache(:nil_key) { call_count += 1; 'not nil' }

      _(call_count).must_equal 1
    end

    it 'returns different values for different keys' do
      a = Lux.ctx.cache(:key_a) { 'a' }
      b = Lux.ctx.cache(:key_b) { 'b' }
      _(a).must_equal 'a'
      _(b).must_equal 'b'
    end
  end

  describe '#no_cache?' do
    it 'returns false by default' do
      _(Lux.ctx.no_cache?).must_equal false
    end

    it 'returns false even with no-cache header when can_clear_cache is not set' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_CACHE_CONTROL' => 'no-cache')
      Lux::Context.new(env)
      refute Lux.ctx.no_cache?
    end

    it 'returns true when no-cache header and can_clear_cache are set' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_CACHE_CONTROL' => 'no-cache')
      Lux::Context.new(env)
      Lux.ctx.can_clear_cache = true
      _(Lux.ctx.no_cache?).must_equal true
    end
  end

  describe '#once' do
    it 'returns true on first call' do
      _(Lux.ctx.once(:action1)).must_equal true
    end

    it 'returns false on subsequent calls with same id' do
      Lux.ctx.once(:action1)
      _(Lux.ctx.once(:action1)).must_equal false
    end

    it 'returns true for different ids' do
      Lux.ctx.once(:action1)
      _(Lux.ctx.once(:action2)).must_equal true
    end

    it 'yields block on first call only' do
      call_count = 0
      Lux.ctx.once(:block_test) { call_count += 1 }
      Lux.ctx.once(:block_test) { call_count += 1 }
      _(call_count).must_equal 1
    end
  end

  describe '#uid' do
    it 'generates incrementing unique IDs' do
      id1 = Lux.ctx.uid
      id2 = Lux.ctx.uid
      _(id1).must_match(/^uid_\d+_\d+$/)
      refute_equal id2, id1
    end

    it 'returns numeric only with num_only flag' do
      num = Lux.ctx.uid(true)
      _(num).must_be_kind_of Integer
    end

    it 'increments the counter' do
      n1 = Lux.ctx.uid(true)
      n2 = Lux.ctx.uid(true)
      _(n2).must_equal(n1 + 1)
    end
  end

  describe '#ip' do
    def current_from addr, cf: nil, forwarded: nil
      env = Rack::MockRequest.env_for('http://test.example.com/', 'REMOTE_ADDR' => addr)
      env['HTTP_CF_CONNECTING_IP'] = cf if cf
      env['HTTP_X_FORWARDED_FOR']  = forwarded if forwarded
      Lux::Context.new(env)
    end

    it 'returns an IP address' do
      _(Lux.ctx.ip).must_be_kind_of String
      refute_empty Lux.ctx.ip
    end

    it 'ignores CF-Connecting-IP from a non Cloudflare peer' do
      _(current_from('203.0.113.9', cf: '127.0.0.1').ip).must_equal '203.0.113.9'
    end

    it 'trusts CF-Connecting-IP from a Cloudflare edge, also behind a local proxy' do
      _(current_from('173.245.48.10', cf: '198.51.100.7').ip).must_equal '198.51.100.7'
      _(current_from('127.0.0.1', cf: '198.51.100.7', forwarded: '173.245.48.10').ip).must_equal '198.51.100.7'
    end
  end

  describe 'CF-* headers' do
    def env_from addr
      Rack::MockRequest.env_for('http://test.example.com/', 'REMOTE_ADDR' => addr, 'HTTP_CF_IPCOUNTRY' => 'DE')
    end

    it 'drops them when the request did not come through Cloudflare' do
      _(Lux::Context.new(env_from('203.0.113.9')).request.env['HTTP_CF_IPCOUNTRY']).must_be_nil
    end

    it 'keeps them from a Cloudflare edge' do
      _(Lux::Context.new(env_from('173.245.48.10')).request.env['HTTP_CF_IPCOUNTRY']).must_equal 'DE'
    end
  end

  describe '#local_request?' do
    it 'is true only for a loopback client' do
      local  = Rack::MockRequest.env_for('http://test.example.com/', 'REMOTE_ADDR' => '127.0.0.1')
      remote = Rack::MockRequest.env_for('http://test.example.com/', 'REMOTE_ADDR' => '203.0.113.9')
      spoof  = Rack::MockRequest.env_for('http://test.example.com/', 'REMOTE_ADDR' => '203.0.113.9', 'HTTP_X_FORWARDED_FOR' => '127.0.0.1')

      assert Lux::Context.new(local).local_request?
      refute Lux::Context.new(remote).local_request?
      refute Lux::Context.new(spoof).local_request?
    end
  end

  describe '#encrypt / #decrypt' do
    it 'encrypts and decrypts data with IP-based password' do
      encrypted = Lux.ctx.encrypt('secret')
      _(encrypted).must_be_kind_of String
      _(Lux.ctx.decrypt(encrypted)).must_equal 'secret'
    end
  end

  describe '#var' do
    it 'provides request-scoped variable storage' do
      Lux.ctx[:custom_var] = 'hello'
      _(Lux.ctx[:custom_var]).must_equal 'hello'
    end
  end

  describe '#robot?' do
    it 'returns false for normal requests' do
      _(Lux.ctx.robot?).must_equal false
    end

    it 'detects wget user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Wget/1.21')
      Lux::Context.new(env)
      _(Lux.ctx.robot?).must_equal true
    end

    it 'detects curl user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'curl/7.79.1')
      Lux::Context.new(env)
      _(Lux.ctx.robot?).must_equal true
    end
  end

  describe '#mobile?' do
    it 'returns false for desktop user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh)')
      Lux::Context.new(env)
      _(Lux.ctx.mobile?).must_equal false
    end

    it 'detects iPhone user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (iPhone; CPU iPhone OS)')
      Lux::Context.new(env)
      _(Lux.ctx.mobile?).must_equal true
    end

    it 'detects Android user agent' do
      env = Rack::MockRequest.env_for('http://test.example.com/', 'HTTP_USER_AGENT' => 'Mozilla/5.0 (Linux; Android 12)')
      Lux::Context.new(env)
      _(Lux.ctx.mobile?).must_equal true
    end
  end

  describe '#files_in_use' do
    it 'tracks files and returns false on first use' do
      result = Lux.ctx.files_in_use('app/models/user.rb')
      _(result).must_equal false
    end

    it 'returns true for already-tracked files' do
      Lux.ctx.files_in_use('app/models/user.rb')
      result = Lux.ctx.files_in_use('app/models/user.rb')
      _(result).must_equal true
    end

    it 'returns the set when called without args' do
      Lux.ctx.files_in_use('app/models/user.rb')
      _(Lux.ctx.files_in_use).must_be_kind_of Set
      _(Lux.ctx.files_in_use).must_include 'app/models/user.rb'
    end
  end
end
