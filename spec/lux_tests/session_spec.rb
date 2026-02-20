require 'spec_helper'

describe Lux::Current::Session do
  before do
    Lux::Current.new('http://test.example.com/')
  end

  let(:session) { Lux.current.session }

  describe '#[] and #[]=' do
    it 'stores and retrieves values' do
      session[:user_id] = 42
      expect(session[:user_id]).to eq(42)
    end

    it 'normalizes keys to lowercase strings' do
      session[:MyKey] = 'value'
      expect(session['mykey']).to eq('value')
    end

    it 'supports string keys' do
      session['token'] = 'abc'
      expect(session['token']).to eq('abc')
    end

    it 'returns nil for missing keys' do
      expect(session[:nonexistent]).to be_nil
    end
  end

  describe '#delete' do
    it 'removes a key from session' do
      session[:temp] = 'data'
      session.delete(:temp)
      expect(session[:temp]).to be_nil
    end
  end

  describe '#merge!' do
    it 'merges a hash into session' do
      session.merge!(name: 'test', role: 'admin')
      expect(session[:name]).to eq('test')
      expect(session[:role]).to eq('admin')
    end
  end

  describe '#keys' do
    it 'returns all session keys' do
      session[:a] = 1
      session[:b] = 2
      expect(session.keys).to include('a', 'b')
    end
  end

  describe '#to_h' do
    it 'returns the session hash' do
      session[:foo] = 'bar'
      h = session.to_h
      expect(h).to be_a(Hash)
      expect(h['foo']).to eq('bar')
    end
  end

  describe '#hash' do
    it 'returns the underlying hash' do
      expect(session.hash).to be_a(Hash)
    end
  end

  describe '#cookie_name' do
    it 'includes the lux prefix' do
      expect(session.cookie_name).to start_with('lux_')
    end

    it 'includes the port number' do
      expect(session.cookie_name).to match(/_\d+$/)
    end
  end

  describe '#generate_cookie' do
    it 'generates an encrypted cookie string' do
      session[:test] = 'data'
      cookie = session.generate_cookie
      expect(cookie).to be_a(String)
      expect(cookie).to include(session.cookie_name)
      expect(cookie).to include('Path=/')
      expect(cookie).to include('HttpOnly')
      expect(cookie).to include('SameSite=Lax')
    end

    it 'includes Max-Age' do
      session[:test] = 'data'
      cookie = session.generate_cookie
      expect(cookie).to match(/Max-Age=\d+/)
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
      expect(cookie2).to be_nil
    end
  end

  describe '#security_string' do
    it 'returns a string based on IP and user agent' do
      result = session.security_string
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe 'security_check' do
    it 'stores security check data in _c key' do
      expect(session['_c']).to be_an(Array)
      expect(session['_c'].length).to eq(2)
    end
  end
end
