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
# Off with `session_dbsc: false`; only active over https and for a host-only
# session cookie (`session_cookie_domain: false`). Chrome scopes the bound
# session to the registering origin, so a sibling subdomain could never refresh
# the proof and would wipe the shared session for the whole domain.

module Lux
  class Context
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

      def enabled? request, session
        Lux.config[:session_dbsc] != false && request.ssl? && !session.cookie_domain
      end

      # Proof cookie name, tied to the session cookie it guards.
      def cookie_name session
        session.cookie_name + '_b'
      end

      # False for a device-bound session without a fresh proof cookie of its own.
      # The refresh endpoint (POST only) is exempt - it is called because the proof expired.
      def proven? request, session
        return true unless session.hash[KEY] && enabled?(request, session)
        return true if request.post? && request.path_info == REFRESH_PATH

        proof = Lux::Utils::Crypt.unseal(request.cookies[cookie_name(session)], purpose: PROOF_PURPOSE)
        proof.is_a?(::Hash) && proof['sid'] == session.hash['sid']
      end

      # Offer registration once per unbound session; nil when there is nothing to offer.
      def registration_header ctx
        session = ctx.session
        return unless enabled?(ctx.request, session)
        return if session[KEY] || session[OFFERED]

        session[OFFERED] = 1
        '(ES256);path="%s";challenge="%s"' % [REGISTER_PATH, challenge(ctx.session_sid)]
      end

      # POST /_lux_/dbsc/* - fills ctx.response. Runs before the CSRF check, the
      # browser posts these on its own.
      def handle ctx
        return unless enabled?(ctx.request, ctx.session)

        case ctx.request.path_info
        when REGISTER_PATH then register ctx
        when REFRESH_PATH  then refresh ctx
        end
      end

      def challenge sid
        Lux::Utils::Crypt.seal({ 'sid' => sid }, ttl: CHALLENGE_TTL, purpose: CHALLENGE_PURPOSE)
      end

      private

      def register ctx
        jwt = proof_jwt(ctx)
        jwk = (JWT.decode(jwt.to_s, nil, false)[1]['jwk'] rescue nil)
        jwk = jwk.slice('kty', 'crv', 'x', 'y') if jwk.is_a?(::Hash)
        payload = verify(jwt, jwk) if jwk

        return reject(ctx, 400) unless payload && challenge_valid?(payload['jti'], ctx.session_sid)

        ctx.session[KEY] = jwk
        prove ctx
      end

      # A bad signature is not this device: 401 makes the browser end the bound
      # session. A missing or stale challenge gets a fresh one with 403, which
      # the browser answers with a new proof.
      def refresh ctx
        session = ctx.session
        sid     = ctx.request.get_header('HTTP_SEC_SECURE_SESSION_ID').to_s.delete('"')
        return reject(ctx, 401) unless session[KEY] && sid == session[:sid]

        if jwt = proof_jwt(ctx)
          payload = verify(jwt, session[KEY]) or return reject(ctx, 401)
          return prove(ctx) if challenge_valid?(payload['jti'], sid)
        end

        ctx.response.header 'secure-session-challenge', '"%s";id="%s"' % [challenge(sid), sid]
        reject ctx, 403
      end

      def prove ctx
        sid  = ctx.session_sid
        name = cookie_name(ctx.session)

        # sealed a minute past the cookie Max-Age, so the browser refreshes before the server rejects
        ctx.response.cookie name, Lux::Utils::Crypt.seal({ 'sid' => sid }, ttl: BOUND_TTL + 60, purpose: PROOF_PURPOSE), max_age: BOUND_TTL
        ctx.response.content_type :json
        ctx.response.body({
          session_identifier: sid,
          refresh_url:        REFRESH_PATH,
          scope:              { include_site: false },
          credentials:        [{ type: 'cookie', name: name, attributes: 'Path=/; Secure; HttpOnly; SameSite=Lax' }]
        })
      end

      def reject ctx, status
        ctx.response.body '', status: status
      end

      def proof_jwt ctx
        ctx.request.get_header('HTTP_SECURE_SESSION_RESPONSE').presence
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
