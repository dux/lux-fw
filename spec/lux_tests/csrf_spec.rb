require 'spec_helper'

describe 'Lux::Current CSRF' do
  def current_for env_extra = {}, method: 'POST', session: {}
    env = ::Rack::MockRequest.env_for('/', method: method)
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
      expect(c.session[:_csrf]).to eq(token)
    end

    it 'returns the same token on subsequent reads within the request' do
      c = current_for
      expect(c.csrf).to eq(c.csrf)
    end

    it 'reuses an existing session token' do
      c = current_for(session: { _csrf: 'abc123' })
      expect(c.csrf).to eq('abc123')
    end
  end

  describe '#csrf_valid?' do
    it 'true when X-CSRF-Token header matches session' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'xyz789' },
                      session: { _csrf: 'xyz789' })
      expect(c.csrf_valid?).to be true
    end

    it 'false when token does not match' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'wrong!' },
                      session: { _csrf: 'right!' })
      expect(c.csrf_valid?).to be false
    end

    it 'false when nothing submitted' do
      c = current_for(session: { _csrf: 'abc123' })
      expect(c.csrf_valid?).to be false
    end

    it 'false when session has no token' do
      c = current_for({ 'HTTP_X_CSRF_TOKEN' => 'abc123' })
      expect(c.csrf_valid?).to be false
    end
  end

  describe '#csrf_required?' do
    it 'false for GET / HEAD / OPTIONS' do
      %w[GET HEAD OPTIONS].each do |m|
        expect(current_for(method: m).csrf_required?).to be false
      end
    end

    it 'true for POST / PUT / PATCH / DELETE' do
      %w[POST PUT PATCH DELETE].each do |m|
        expect(current_for(method: m).csrf_required?).to be true
      end
    end

    it 'false when Authorization: Bearer is present' do
      c = current_for({ 'HTTP_AUTHORIZATION' => 'Bearer abc.def.ghi' })
      expect(c.csrf_required?).to be false
    end
  end
end
