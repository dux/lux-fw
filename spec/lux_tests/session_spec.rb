require 'test_helper'

describe Lux::Current::Session do
  before do
    Lux::Current.new('http://test.example.com/')
  end

  def session
    @session ||= Lux.current.session
  end

  describe '#[] and #[]=' do
    it 'stores and retrieves values' do
      session[:user_id] = 42
      _(session[:user_id]).must_equal 42
    end

    it 'normalizes keys to lowercase strings' do
      session[:MyKey] = 'value'
      _(session['mykey']).must_equal 'value'
    end

    it 'supports string keys' do
      session['token'] = 'abc'
      _(session['token']).must_equal 'abc'
    end

    it 'returns nil for missing keys' do
      _(session[:nonexistent]).must_be_nil
    end
  end

  describe '#delete' do
    it 'removes a key from session' do
      session[:temp] = 'data'
      session.delete(:temp)
      _(session[:temp]).must_be_nil
    end
  end

  describe '#merge!' do
    it 'merges a hash into session' do
      session.merge!(name: 'test', role: 'admin')
      _(session[:name]).must_equal 'test'
      _(session[:role]).must_equal 'admin'
    end
  end

  describe '#keys' do
    it 'returns all session keys' do
      session[:a] = 1
      session[:b] = 2
      _(session.keys).must_include 'a'
      _(session.keys).must_include 'b'
    end
  end

  describe '#to_h' do
    it 'returns the session hash' do
      session[:foo] = 'bar'
      h = session.to_h
      _(h).must_be_kind_of Hash
      _(h['foo']).must_equal 'bar'
    end
  end

  describe '#hash' do
    it 'returns the underlying hash' do
      _(session.hash).must_be_kind_of Hash
    end
  end

  describe '#cookie_name' do
    it 'includes the lux prefix' do
      _(session.cookie_name).must_match(/\Alux_/)
    end

    it 'includes the port number' do
      _(session.cookie_name).must_match(/_\d+$/)
    end
  end

  describe '#generate_cookie' do
    it 'generates an encrypted cookie string' do
      session[:test] = 'data'
      cookie = session.generate_cookie
      _(cookie).must_be_kind_of String
      _(cookie).must_include session.cookie_name
      _(cookie).must_include 'Path=/'
      _(cookie).must_include 'HttpOnly'
      _(cookie).must_include 'SameSite=Lax'
    end

    it 'includes Max-Age' do
      session[:test] = 'data'
      cookie = session.generate_cookie
      _(cookie).must_match(/Max-Age=\d+/)
    end

    it 'returns nil when session unchanged' do
      # First call sets the cookie, second with same data returns nil
      cookie1 = session.generate_cookie

      # Recreate with the cookie set
      env = Rack::MockRequest.env_for('http://test.example.com/')
      if cookie1
        name, value = cookie1.split(';').first.split('=', 2)
        env['HTTP_COOKIE'] = "#{name}=#{value}"
      end

      Lux::Current.new(env)
      cookie2 = Lux.current.session.generate_cookie
      _(cookie2).must_be_nil
    end
  end

  describe '#security_string' do
    it 'returns a string based on IP and user agent' do
      result = session.security_string
      _(result).must_be_kind_of String
      _(result.empty?).must_equal false
    end
  end

  describe 'security_check' do
    it 'stores security check data in _c key' do
      _(session['_c']).must_be_kind_of Array
      _(session['_c'].length).must_equal 2
    end
  end
end
