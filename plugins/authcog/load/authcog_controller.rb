require 'net/http'

# Central-auth sign-in for AuthCog. A single controller, mapped once at /authcog:
#
#   GET /authcog                  -> start the login (mint a challenge, hand off)
#   GET /authcog?callback=<hash>  -> exchange the hash and sign the user in
#
# Central auth sends the browser back to /authcog?callback=<40-char-hash>; we
# exchange it server-side at https://auth.authcog.com/domain:<host> for
# { email, name, avatar, provider } and start a local session.
#
# Wire up in routes.rb:
#   map 'authcog', 'authcog#call'

class AuthcogController < Lux::Controller
  SESSION_STATE ||= :authcog_state

  # How many outstanding challenges a browser may hold. More than one because a
  # visitor can open the sign-in link in several tabs before finishing in any of
  # them, and each of those has to stay usable.
  CHALLENGE_LIMIT ||= 4

  # Where a "sign in" link points: this controller's own mount path. Deliberately
  # a plain local path with no secret in it, so it can be rendered into a shared
  # or cached page and linked from a view. The challenge is minted when the link
  # is followed (#start), not when it is drawn.
  def self.auth_link
    Lux.config[:authcog_path] || '/authcog'
  end

  # Absolute central-auth endpoint for this host. Used both to send the visitor
  # there and to exchange the returned hash server to server.
  def self.exchange_base here = Url.current
    path = "/domain:#{here.host}"
    path += "/port:#{here.port}" if here.port

    realm = Lux.config[:authcog_realm] || :auth
    "https://#{realm}.authcog.com#{path}"
  end

  def call
    action params[:callback] ? :callback : :start
  end

  # GET /authcog - begin a login. The challenge goes in this browser's session and
  # rides along to central auth, which echoes it back on the callback; a sign-in
  # this browser never started is then refused (see #callback, RFC 9700).
  def start
    state = SecureRandom.urlsafe_base64(24)
    held  = Array(session[SESSION_STATE])
    session[SESSION_STATE] = (held + [state]).last(CHALLENGE_LIMIT)

    redirect_to "#{self.class.exchange_base}?state=#{Rack::Utils.escape(state)}"
  end

  # Verify the ?check= hash against the session, end it, back to /.
  # Checks session[:user_ref] directly (not User.current): this action runs on
  # AuthcogController, which the app's user-loading before-filter never touches,
  # so it must not depend on the current user being resolved.
  #
  # Not routed by default - UserSession#logout_link (?sso_action=) is the
  # supported path. Mount it explicitly if you want the bare URL:
  #   map 'log-off', 'authcog#log_off'
  def log_off
    ref = Lux::Utils::Crypt.short_decrypt(params[:check].to_s) rescue nil
    UserSession.destroy_session if ref && ref == session[:user_ref]
    redirect_to '/', info: 'Signed out'
  end

  # GET /authcog?callback=<hash>&state=<challenge> - exchange the single-use hash
  # and sign in. The challenge is the one #auth_link put in this browser's session,
  # so an attacker cannot land their own login in someone else's browser.
  def callback
    callback_hash = params[:callback].to_s
    raise Lux.error.bad_request('Missing callback') unless callback_hash =~ /\A[A-Za-z0-9]{40}\z/

    unless claim_challenge(params[:state])
      raise Lux.error.bad_request('Unsolicited or expired login - please sign in again')
    end

    data = fetch_identity(callback_hash)
    raise Lux.error.bad_request("AuthCog returned no email") if data[:email].blank?

    Lux.logger(:authcog).info "central-auth login - #{data[:email]} (#{data[:provider]})"

    User.current = User.quick_create(data[:email])

    if user.is_locked
      return redirect_to '/', error: 'You are locked and you are not allowed to log in.'
    end

    session[:user_ref] = user.ref

    user.name ||= data[:name]
    user.is_deleted = false
    user.save

    # Store the provider avatar as given. Re-hosting it is an app concern -
    # the old CDN upload here called a constant no plugin defines.
    if data[:avatar] && user.respond_to?(:cached_avatar) && user.cached_avatar.blank?
      user[:cached_avatar] = data[:avatar]
      user.save
    end

    target = session.delete(:redirect_after_login) || '/'
    redirect_to "#{target}?login=authcog"
  end

  private

  # True when `given` is one of the challenges this browser is holding, which it
  # then spends. Only a match is removed: a bogus ?state= must not be able to
  # clear a real one and lock the visitor out of signing in.
  def claim_challenge given
    given = given.to_s
    return false if given.empty?

    held = Array(session[SESSION_STATE])
    hit  = held.find { |s| Rack::Utils.secure_compare(s.to_s, given) }
    return false unless hit

    session[SESSION_STATE] = held - [hit]
    true
  end

  def user
    User.current
  end

  def fetch_identity callback_hash
    # Exchange is scoped to the relying domain: central auth only releases the
    # hash to the same host it was issued for (this request's own host).
    uri = URI("#{self.class.exchange_base}?user=#{callback_hash}")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.get(uri.request_uri)
    end

    case res.code.to_i
    when 200
      JSON.parse(res.body, symbolize_names: true)
    when 404
      raise Lux.error.bad_request('AuthCog callback unknown - expired session?')
    when 410
      raise Lux.error.bad_request('AuthCog callback already used or expired')
    else
      raise Lux.error.bad_request("AuthCog exchange failed (#{res.code})")
    end
  end
end
