require_relative '../lib/authcog'

# Central-auth sign-in for AuthCog. A single router, mapped once at /authcog:
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

class AuthcogRouter < Lux::Router
  SESSION_STATE ||= :authcog_state

  # Marks the one automatic restart a failed challenge is allowed, so a callback
  # that keeps coming back wrong ends on the error rather than in a loop.
  SESSION_RETRY ||= :authcog_retry

  # Where a "sign in" link points: this router's own mount path. Deliberately
  # a plain local path with no secret in it, so it can be rendered into a shared
  # or cached page and linked from a view. The challenge is minted when the link
  # is followed (#start), not when it is drawn.
  def self.auth_link
    Lux.config[:authcog_path] || '/authcog'
  end

  # Absolute central-auth endpoint for this host. Used both to send the visitor
  # there and to exchange the returned hash server to server.
  #
  # The host comes from the request, so it is trusted only inside the app's own
  # configured domain (subdomains included). Otherwise a forged Host header
  # would pick the domain a callback hash is exchanged for, and a hash leaked
  # from another site could be spent here.
  def self.exchange_base here = Url.current
    url = Authcog.relying_url(here)
    Authcog.auth_url(url.host, url.port)
  end

  def call
    action params[:callback] ? :callback : :start
  end

  # GET /authcog - begin a login. The challenge goes in this browser's session and
  # rides along to central auth, which echoes it back on the callback; a sign-in
  # this browser never started is then refused (see #callback, RFC 9700).
  def start
    state = Authcog.mint_challenge(session, SESSION_STATE)
    redirect_to "#{self.class.exchange_base}?state=#{Rack::Utils.escape(state)}"
  end

  # GET /authcog?callback=<hash>&state=<challenge> - exchange the single-use hash
  # and sign in. The challenge is the one #auth_link put in this browser's session,
  # so an attacker cannot land their own login in someone else's browser.
  def callback
    callback_hash = params[:callback].to_s
    raise Lux.error.bad_request('Missing callback') unless callback_hash =~ /\A[A-Za-z0-9]{40}\z/

    # A challenge this browser is not holding is not always an attack: a callback
    # opened twice, or a stale one echoed by central auth, lands here too. Send
    # the visitor back through the front door once instead of leaving them on an
    # error page - the retry mints a fresh challenge, so nothing is signed in
    # that this browser did not ask for.
    unless Authcog.claim_challenge(session, SESSION_STATE, params[:state])
      if session[SESSION_RETRY]
        session.delete SESSION_RETRY
        raise Lux.error.bad_request('Unsolicited or expired login - please sign in again')
      end

      session[SESSION_RETRY] = true
      return redirect_to self.class.auth_link
    end

    session.delete SESSION_RETRY

    data = fetch_identity(callback_hash)
    raise Lux.error.bad_request("AuthCog returned no email") if data[:email].blank?

    Lux.logger(:authcog).info "central-auth login - #{data[:email]} (#{data[:provider]})"

    User.current = User.quick_create(data[:email])

    if user.is_locked
      return redirect_to '/', error: 'You are locked and you are not allowed to log in.'
    end

    UserSession.login_user_ref user.ref

    user.name ||= data[:name]
    user.is_deleted = false
    user.save

    # Store the provider avatar as given. Re-hosting it is an app concern -
    # the old CDN upload here called a constant no plugin defines.
    if data[:avatar] && user.respond_to?(:cached_avatar) && user.cached_avatar.blank?
      user[:cached_avatar] = data[:avatar]
      user.save
    end

    target = UserSession.local_path(session.delete(:redirect_after_login)) || '/'
    redirect_to Url.new(target).qs(:login, :authcog).to_s
  end

  private

  def user
    User.current
  end

  def fetch_identity callback_hash
    # Exchange is scoped to the relying domain: central auth only releases the
    # hash to the host it was issued for, guarded the same as #exchange_base.
    here = Authcog.relying_url(Url.current)
    Authcog.exchange(callback_hash, host: here.host, port: here.port)
  rescue Authcog::Error => e
    raise Lux.error.bad_request(e.message)
  end
end
