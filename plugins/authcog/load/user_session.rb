# Shared browser session + admin "sudo as" support for authcog apps.
#
# Identity is keyed on user.ref. The ?sso_action= param carries a sealed
# hash { action: 'login' | 'sudo_as' | 'logout', ref: ... } that resolve()
# unseals and dispatches on the next request; ?sso_action=false clears a sudo
# overlay. Links are plain URLs, so they work in mailers and across hosts.
# Sudo is an overlay: the target wins everywhere except /admin, where the real
# admin identity is kept.

module UserSession
  extend self
  extend Lux::Lifecycle

  USER_REF      ||= :user_ref
  SUDO_USER_REF ||= :sudo_user_ref
  SSO_PURPOSE   ||= 'sso_action'
  API_KEY_CACHE_TTL ||= 1.hour

  def resolve
    return resolve_bearer(Lux.ctx.bearer_token) if Lux.ctx.bearer_token

    ref = session_ref
    load_user_by_ref ref if ref

    if token = params[:sso_action]
      resolve_sso_action token
    elsif params[:uref] && impersonate?
      uref = params[:uref]
      ref  = uref.include?('@') ? User.find_by(email: uref)&.ref : uref
      login_user_ref ref if ref
      redirect_to request.path
    end
  end

  # Dev-only powers - ?uref=, Bearer <email>, sudo without being admin,
  # /dev/login_as. Needs the dev env AND a client on this machine: dev? is just
  # "not production", so LUX_ENV alone would open them on staging/test deploys.
  def impersonate?
    Lux.env.dev? && Lux.ctx.local_request?
  end

  # Load a user by API key. Caches key -> ref; cache hits reload via User.take(ref).
  # Sleeps 200ms on a miss to slow down brute-force guessing.
  def api_key_load api_key
    return unless api_key

    cache_key = api_key_cache_key(api_key)
    if ref = Lux.cache.get(cache_key)
      if user = User.take(ref)
        return user if user.api_key == api_key
      end
      Lux.cache.delete cache_key
    end

    user = User.find_by(api_key: api_key)
    unless user
      sleep 0.2
      return nil
    end

    Lux.cache.set cache_key, user.ref, API_KEY_CACHE_TTL.to_i
    user
  end

  # login magic link (mailers, cross-host, dev/admin login-as). One-time: the
  # nonce is marked spent in Lux.cache on first use, so a forwarded or logged
  # link cannot sign in again within its TTL.
  # subdomain: builds an absolute link on that subdomain of the current host.
  def login_link user, path: nil, ttl: nil, subdomain: nil
    ref   = user.is_a?(String) ? user : user.ref
    ttl   = (ttl || 1.hour).to_i
    token = sso_action_token(:login, ref: ref, ttl: ttl, n: Lux::Utils::Crypt.uid(16), x: ttl)

    return '%s?sso_action=%s' % [path || '/', token] unless subdomain

    Lux.ctx.url.subdomain(subdomain).path(path || '/').qs('sso_action', token).url
  end

  # admins only: start a sudo overlay
  def sudo_login_link user, path: nil
    '%s?sso_action=%s' % [path || '/', sso_action_token(:sudo_as, ref: user.ref, ttl: 1.minute)]
  end

  # end the session; resolve() consumes the logout action (replaces /log-off)
  def logout_link where = nil
    '%s?sso_action=%s' % [where || '/', sso_action_token(:logout, ref: User.current.ref, ttl: 5.minutes)]
  end

  def sudo?
    session[SUDO_USER_REF].present?
  end
  alias_method :sudo_user?, :sudo?

  # Admin sudo banner: a thin red bar naming the impersonated user plus a
  # one-click "sudo off". Returns nil unless a sudo overlay is active, so a
  # layout can drop `= UserSession.sudo_bar` at the very top of %body and it
  # stays invisible for normal sessions. The link hits ?sso_action=false,
  # which resolve() maps to clearing the overlay (see action_sudo_off).
  def sudo_bar
    return unless sudo?
    user  = User.take(session[SUDO_USER_REF]) or return
    label = ::Rack::Utils.escape_html(user.name.presence || user.email)
    Lux::SafeString.new %[<div style="background:#c0392b;color:#fff;font:13px/1.4 sans-serif;padding:6px 12px;text-align:center;">] +
      %[Sudo as <b>#{label}</b> &middot; ] +
      %[<a href="?sso_action=false" style="color:#fff;text-decoration:underline;">sudo off</a></div>]
  end

  def login_user_ref ref
    session[USER_REF] = ref
    session.delete SUDO_USER_REF
    Lux.ctx.rotate_csrf!
    load_user_by_ref ref
  end

  def destroy_session
    session.delete USER_REF
    session.delete SUDO_USER_REF
    User.current = nil
  end

  def redirect_after_login= location
    session[:redirect_after_login] = local_path(location)
  end

  # `path` when it stays on this site, else nil. "//host" and "/\\host" are
  # protocol-relative to browsers, so they count as leaving.
  def local_path path
    path = path.to_s
    path if path.match?(%r{\A/(?![/\\])}) && !path.match?(/[[:cntrl:]]/)
  end

  def redirect_after_login! where = nil
    if location = local_path(session.delete(:redirect_after_login))
      redirect_to location
    elsif where
      redirect_to where
    else
      false
    end
  end

  private

  # encode the ?sso_action= token: { action:, ... } sealed with a TTL
  def sso_action_token action, ttl:, **data
    Lux::Utils::Crypt.seal({ 'action' => action.to_s }.merge(data.transform_keys(&:to_s)), ttl: ttl, purpose: SSO_PURPOSE)
  end

  # unseal ?sso_action= and dispatch to action_<name>
  def resolve_sso_action token
    return action_sudo_off if token == 'false'

    data = Lux::Utils::Crypt.unseal(token, purpose: SSO_PURPOSE)
    return unless data.is_a?(::Hash)

    case data['action']
    when 'login'   then action_login   data
    when 'sudo_as' then action_sudo_as data
    when 'logout'  then action_logout  data
    end
  end

  # The spent mark is not atomic; a racing double click both sign in the same user.
  def action_login data
    used = 'authcog:login-link:%s' % data['n']
    return redirect_to('/', error: 'Login link already used') if data['n'].blank? || Lux.cache.get(used)

    Lux.cache.set used, 1, data['x'].to_i
    user = User.take(data['ref']) or return redirect_to('/', error: 'User cant be loaded')
    login_user_ref user.ref
    redirect_to request.path, info: 'Loged in as %s' % user.email
  end

  def action_sudo_as data
    User.current = User.take(session[USER_REF])   # real identity, not a sudo overlay
    return response.flash.error('Sudo error') unless User.current && (User.current.can.admin? || impersonate?)

    target = User.take(data['ref'])
    if target && target.ref != User.current.ref
      session[SUDO_USER_REF] = target.ref
      resolve_redirect 'Sudoing as %s' % target.name
    else
      response.flash.error 'Sudo error'
    end
  end

  def action_logout data
    destroy_session if data['ref'] == session[USER_REF]
    redirect_to '/', info: 'Signed out'
  end

  def action_sudo_off
    session.delete SUDO_USER_REF
    redirect_to request.path, info: 'Sudoing canceled'
  end

  # sudo overlay wins except under /admin (keep the real admin there)
  def session_ref
    base = session[USER_REF]
    sudo = session[SUDO_USER_REF]
    return base if base && sudo && Lux.ctx.nav.path.first == 'admin'
    sudo || base
  end

  def resolve_bearer bearer
    if impersonate? && bearer.include?('@')
      User.current = User.find_by(email: bearer)
    elsif User.columns.include?(:api_key)
      Lux.logger.error "Bad bearer token: #{bearer}" unless User.current = api_key_load(bearer)
    end
  end

  def load_user_by_ref ref
    User.current = User.take(ref)
    Lux.ctx.can_clear_cache ||= true if User.current && (Lux.env.dev? || User.current.can.admin?)
  end

  def api_key_cache_key api_key
    "api-key-ref:#{Digest::SHA256.hexdigest(api_key)}"
  end

  def resolve_redirect info = nil
    if session[USER_REF]
      redirect_to local_path(session.delete(:redirect_after_login)) || request.path, info: info
    else
      redirect_to '/', error: 'Session ended, please login again'
    end
  end
end
