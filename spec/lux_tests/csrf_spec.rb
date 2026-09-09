require 'test_helper'

describe 'Lux::Current CSRF' do
  # A session cookie is what makes a request forgeable, so most of these need one.
  # `cookie: false` builds the bare machine-to-machine shape instead.
  def current_for env_extra = {}, method: 'POST', session: {}, cookie: true, params: nil
    env = ::Rack::MockRequest.env_for('/', method: method, **(params ? { params: params } : {}))
    # the cookie name is derived per request, so ask a throwaway Current for it
    env['HTTP_COOKIE'] = "#{Lux::Current.new(env).session.cookie_name}=x" if cookie
    env.merge! env_extra
    c = Lux::Current.new env
    session.each { |k, v| c.session[k] = v }
    c
  end

  describe '#csrf' do
    it 'generates and persists a 6-char token on first read' do
      c = current_for
      token = c.csrf
      expect(token).to match(/\A[a-z0-9]{6}\z/)
      expect(c.session[:_csrf]).to eq token
    end

    it 'returns the same token on subsequent reads within the request' do
      c = current_for
      expect(c.csrf).to eq c.csrf
    end

    it 'reuses an existing session token' do
      c = current_for(session: { _csrf: 'abc123' })
      expect(c.csrf).to eq 'abc123'
    end
  end

  describe '#csrf_valid?' do
    it 'true when X-CSRF-Token header matches session' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'xyz789' },
                      session: { _csrf: 'xyz789' })
      expect(c.csrf_valid?).to eq true
    end

    it 'true when the _csrf form field matches session' do
      c = current_for(params: { '_csrf' => 'xyz789' }, session: { _csrf: 'xyz789' })
      expect(c.csrf_valid?).to eq true
    end

    it 'false when token does not match' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'wrong!' },
                      session: { _csrf: 'right!' })
      expect(c.csrf_valid?).to eq false
    end

    it 'false when nothing submitted' do
      c = current_for(session: { _csrf: 'abc123' })
      expect(c.csrf_valid?).to eq false
    end

    it 'false when session has no token' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'abc123' })
      expect(c.csrf_valid?).to eq false
    end
  end

  describe '#csrf_required?' do
    it 'false for GET / HEAD / OPTIONS' do
      %w[GET HEAD OPTIONS].each do |m|
        expect(current_for(method: m).csrf_required?).to eq false
      end
    end

    it 'true for POST / PUT / PATCH / DELETE carrying a session cookie' do
      %w[POST PUT PATCH DELETE].each do |m|
        expect(current_for(method: m).csrf_required?).to eq true
      end
    end

    it 'false when Authorization: Bearer is present' do
      c = current_for({ 'HTTP_AUTHORIZATION' => 'Bearer abc.def.ghi' })
      expect(c.csrf_required?).to eq false
    end

    # forgery works by making a browser spend credentials it already holds; a
    # request with no session cookie has none to spend. This is what lets a
    # webhook authenticated by a shared header token POST at all.
    it 'false when the request carries no session cookie' do
      expect(current_for(cookie: false).csrf_required?).to eq false
    end
  end
end
