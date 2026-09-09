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
      _(token).must_match(/\A[a-z0-9]{6}\z/)
      _(c.session[:_csrf]).must_equal token
    end

    it 'returns the same token on subsequent reads within the request' do
      c = current_for
      _(c.csrf).must_equal c.csrf
    end

    it 'reuses an existing session token' do
      c = current_for(session: { _csrf: 'abc123' })
      _(c.csrf).must_equal 'abc123'
    end
  end

  describe '#csrf_valid?' do
    it 'true when X-CSRF-Token header matches session' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'xyz789' },
                      session: { _csrf: 'xyz789' })
      _(c.csrf_valid?).must_equal true
    end

    it 'true when the _csrf form field matches session' do
      c = current_for(params: { '_csrf' => 'xyz789' }, session: { _csrf: 'xyz789' })
      _(c.csrf_valid?).must_equal true
    end

    it 'false when token does not match' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'wrong!' },
                      session: { _csrf: 'right!' })
      _(c.csrf_valid?).must_equal false
    end

    it 'false when nothing submitted' do
      c = current_for(session: { _csrf: 'abc123' })
      _(c.csrf_valid?).must_equal false
    end

    it 'false when session has no token' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'abc123' })
      _(c.csrf_valid?).must_equal false
    end
  end

  describe '#csrf_required?' do
    it 'false for GET / HEAD / OPTIONS' do
      %w[GET HEAD OPTIONS].each do |m|
        _(current_for(method: m).csrf_required?).must_equal false
      end
    end

    it 'true for POST / PUT / PATCH / DELETE carrying a session cookie' do
      %w[POST PUT PATCH DELETE].each do |m|
        _(current_for(method: m).csrf_required?).must_equal true
      end
    end

    it 'false when Authorization: Bearer is present' do
      c = current_for({ 'HTTP_AUTHORIZATION' => 'Bearer abc.def.ghi' })
      _(c.csrf_required?).must_equal false
    end

    # forgery works by making a browser spend credentials it already holds; a
    # request with no session cookie has none to spend. This is what lets a
    # webhook authenticated by a shared header token POST at all.
    it 'false when the request carries no session cookie' do
      _(current_for(cookie: false).csrf_required?).must_equal false
    end
  end
end
