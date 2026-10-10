# Device Bound Session Credentials - https://w3c.github.io/webappsec-dbsc/
#
# Chrome/Edge keep a non-exportable (TPM) key per session and have to sign a
# challenge to renew a short-lived proof cookie, so a session cookie copied off
# the device dies within BOUND_TTL. Stateless: the device public key rides in the
# sealed session ('_k'), the proof cookie is the sealed sid. Browsers without
# DBSC ignore the registration header and keep the plain session cookie.
#
#   any response               Secure-Session-Registration: (ES256);path="/_lux_/dbsc/register";challenge="..."
#   POST /_lux_/dbsc/register  Secure-Session-Response: <jwt + jwk>    -> key stored, proof cookie, 200 JSON
#   POST /_lux_/dbsc/refresh   Sec-Secure-Session-Id: <sid>             -> 403 + Secure-Session-Challenge
#                              + Secure-Session-Response: <signed jwt>  -> new proof cookie, 200 JSON
#
# Off with `session_dbsc: false`; only active over https.

module Lux
  class Current
    module Dbsc
      PREFIX        ||= '/_lux_/dbsc/'
      REGISTER_PATH ||= '/_lux_/dbsc/register'
      REFRESH_PATH  ||= '/_lux_/dbsc/refresh'
      BOUND_TTL     ||= 10.minutes.to_i
      CHALLENGE_TTL ||= 5.minutes.to_i
      KEY           ||= '_k' # session: public JWK of the bound device
      OFFERED       ||= '_r' # session: registration header already sent

      # Distinct purposes: the challenge is public, so it must never unseal as a proof.
      PROOF_PURPOSE     ||= 'dbsc_proof'
      CHALLENGE_PURPOSE ||= 'dbsc_challenge'

      extend self

      def enabled? request
        Lux.config[:session_dbsc] != false && request.ssl?
      end

      # Proof cookie name, tied to the session cookie it guards.
      def cookie_name session
        session.cookie_name + '_b'
      end

      # False for a device-bound session without a fresh proof cookie of its own.
      # The refresh endpoint is exempt - it is called because the proof expired.
      def proven? request, session
        return true unless session.hash[KEY] && enabled?(request)
        return true if request.path_info == REFRESH_PATH

        proof = Lux::Utils::Crypt.unseal(request.cookies[cookie_name(session)], purpose: PROOF_PURPOSE)
        proof.is_a?(::Hash) && proof['sid'] == session.hash['sid']
      end

      # Offer registration once per unbound session; nil when there is nothing to offer.
      def registration_header current
        session = current.session
        return unless enabled?(current.request)
        return if session[KEY] || session[OFFERED]

        session[OFFERED] = 1
        '(ES256);path="%s";challenge="%s"' % [REGISTER_PATH, challenge(current.session_sid)]
      end

      # POST /_lux_/dbsc/* - fills lux.response. Runs before the CSRF check, the
      # browser posts these on its own.
      def handle lux
        return unless enabled?(lux.request)

        case lux.request.path_info
        when REGISTER_PATH then register lux
        when REFRESH_PATH  then refresh lux
        end
      end

      def challenge sid
        Lux::Utils::Crypt.seal({ 'sid' => sid }, ttl: CHALLENGE_TTL, purpose: CHALLENGE_PURPOSE)
      end

      private

      def register lux
        jwt = proof_jwt(lux)
        jwk = (JWT.decode(jwt.to_s, nil, false)[1]['jwk'] rescue nil)
        jwk = jwk.slice('kty', 'crv', 'x', 'y') if jwk.is_a?(::Hash)
        payload = verify(jwt, jwk) if jwk

        return reject(lux, 400) unless payload && challenge_valid?(payload['jti'], lux.session_sid)

        lux.session[KEY] = jwk
        prove lux
      end

      # A bad signature is not this device: 401 makes the browser end the bound
      # session. A missing or stale challenge gets a fresh one with 403, which
      # the browser answers with a new proof.
      def refresh lux
        session = lux.session
        sid     = lux.request.get_header('HTTP_SEC_SECURE_SESSION_ID').to_s.delete('"')
        return reject(lux, 401) unless session[KEY] && sid == session[:sid]

        if jwt = proof_jwt(lux)
          payload = verify(jwt, session[KEY]) or return reject(lux, 401)
          return prove(lux) if challenge_valid?(payload['jti'], sid)
        end

        lux.response.header 'secure-session-challenge', '"%s";id="%s"' % [challenge(sid), sid]
        reject lux, 403
      end

      def prove lux
        sid  = lux.session_sid
        name = cookie_name(lux.session)

        # sealed a minute past the cookie Max-Age, so the browser refreshes before the server rejects
        lux.response.cookie name, Lux::Utils::Crypt.seal({ 'sid' => sid }, ttl: BOUND_TTL + 60, purpose: PROOF_PURPOSE), max_age: BOUND_TTL
        lux.response.content_type :json
        lux.response.body({
          session_identifier: sid,
          refresh_url:        REFRESH_PATH,
          scope:              { include_site: false },
          credentials:        [{ type: 'cookie', name: name, attributes: 'Path=/; Secure; HttpOnly; SameSite=Lax' }]
        })
      end

      def reject lux, status
        lux.response.body '', status: status
      end

      def proof_jwt lux
        lux.request.get_header('HTTP_SECURE_SESSION_RESPONSE').presence
      end

      # Payload of a dbsc+jwt signed by `jwk`, else nil. Both come from the
      # client, so anything malformed is a plain reject.
      def verify jwt, jwk
        return unless jwk['kty'] == 'EC' && jwk['crv'] == 'P-256'

        key = JWT::JWK.import(jwk).verify_key
        payload, header = JWT.decode(jwt, key, true, algorithm: 'ES256')
        payload if header['typ'] == 'dbsc+jwt'
      rescue StandardError
        nil
      end

      def challenge_valid? token, sid
        data = Lux::Utils::Crypt.unseal(token.to_s, purpose: CHALLENGE_PURPOSE)
        data.is_a?(::Hash) && data['sid'] == sid
      end
    end
  end
end
