require 'test_helper'

describe Lux::Current::Dbsc do
  HOST ||= 'https://test.example.com'
  DBSC ||= Lux::Current::Dbsc

  def device_key
    @device_key ||= OpenSSL::PKey::EC.generate('prime256v1')
  end

  def jwk
    @jwk ||= JWT::JWK.new(device_key).export.slice(:kty, :crv, :x, :y).transform_keys(&:to_s)
  end

  def proof jti, key: device_key, with_jwk: false
    header = { typ: 'dbsc+jwt' }
    header[:jwk] = jwk if with_jwk
    JWT.encode({ jti: jti }, key, 'ES256', header)
  end

  def session_cookie_name
    @session_cookie_name ||= Lux::Current.new("#{HOST}/").session.cookie_name
  end

  # Cookie header carrying a sealed session (plus an optional proof cookie)
  def cookies session, proof_for: nil
    list = ["#{session_cookie_name}=#{Lux::Utils::Crypt.seal(session, purpose: 'session')}"]
    if proof_for
      list << "#{session_cookie_name}_b=#{Lux::Utils::Crypt.seal({ 'sid' => proof_for }, purpose: DBSC::PROOF_PURPOSE)}"
    end
    list.join('; ')
  end

  def bound_session
    { 'sid' => 'sid1', DBSC::KEY => jwk }
  end

  describe '.registration_header' do
    it 'offers registration once per session over https' do
      current = Lux::Current.new("#{HOST}/")
      _(DBSC.registration_header(current)).must_match(%r{\A\(ES256\);path="/_lux_/dbsc/register";challenge="[\w-]+"\z})
      _(DBSC.registration_header(current)).must_be_nil
    end

    it 'does not offer over http' do
      _(DBSC.registration_header(Lux::Current.new('http://test.example.com/'))).must_be_nil
    end
  end

  describe 'register' do
    it 'stores the device key and sets the proof cookie' do
      resp = Lux.render.post("#{HOST}/_lux_/dbsc/register", headers: {
        'Cookie' => cookies({ 'sid' => 'sid1' }),
        'Secure-Session-Response' => proof(DBSC.challenge('sid1'), with_jwk: true)
      })

      assert_status 200, resp
      _(resp.json[:session_identifier]).must_equal 'sid1'
      _(JSON.parse(resp.body).dig('credentials', 0, 'name')).must_equal "#{session_cookie_name}_b"
      _(Array(resp.headers['set-cookie']).join("\n")).must_include "#{session_cookie_name}_b="
      _(resp.session[DBSC::KEY]).must_equal jwk
    end

    it 'rejects a challenge issued for another session' do
      resp = Lux.render.post("#{HOST}/_lux_/dbsc/register", headers: {
        'Cookie' => cookies({ 'sid' => 'sid1' }),
        'Secure-Session-Response' => proof(DBSC.challenge('other'), with_jwk: true)
      })

      assert_status 400, resp
      _(resp.session[DBSC::KEY]).must_be_nil
    end
  end

  describe 'refresh' do
    def refresh proof_jwt = nil, sid: 'sid1'
      headers = { 'Cookie' => cookies(bound_session), 'Sec-Secure-Session-Id' => %["#{sid}"] }
      headers['Secure-Session-Response'] = proof_jwt if proof_jwt
      Lux.render.post("#{HOST}/_lux_/dbsc/refresh", headers: headers)
    end

    it 'answers a bare refresh with a challenge' do
      resp = refresh
      assert_status 403, resp
      _(resp.headers['secure-session-challenge']).must_match(/\A"[\w-]+";id="sid1"\z/)
    end

    it 'renews the proof cookie for a proof signed by the device' do
      resp = refresh proof(DBSC.challenge('sid1'))
      assert_status 200, resp
      _(Array(resp.headers['set-cookie']).join("\n")).must_include "#{session_cookie_name}_b="
    end

    it 'ends the bound session for a proof signed by another key' do
      other = OpenSSL::PKey::EC.generate('prime256v1')
      assert_status 401, refresh(proof(DBSC.challenge('sid1'), key: other))
    end

    it 'ends the bound session for another session id' do
      assert_status 401, refresh(sid: 'other')
    end
  end

  describe 'bound session' do
    def session_with cookie_header
      env = Rack::MockRequest.env_for("#{HOST}/", 'HTTP_COOKIE' => cookie_header)
      Lux::Current.new(env).session
    end

    it 'is kept with a fresh proof cookie' do
      _(session_with(cookies(bound_session, proof_for: 'sid1'))[:sid]).must_equal 'sid1'
    end

    it 'is emptied without a proof cookie' do
      _(session_with(cookies(bound_session))[:sid]).must_be_nil
    end

    it 'is emptied with the proof of another session' do
      _(session_with(cookies(bound_session, proof_for: 'other'))[:sid]).must_be_nil
    end
  end
end
