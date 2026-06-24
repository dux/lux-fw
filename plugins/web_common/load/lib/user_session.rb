# Shared browser session + admin "sudo as" support for web_common apps.
#
# Identity is keyed on user.ref. The ?sso_action= param carries an encrypted
# hash { action: 'login' | 'sudo_as' | 'logout', ref: ... } that resolve()
# decrypts and dispatches on the next request; ?sso_action=false clears a sudo
# overlay. Links are plain URLs, so they work in mailers and across hosts.
# Sudo is an overlay: the target wins everywhere except /admin, where the real
# admin identity is kept.
#
# Apps with bespoke session logic (e.g. cms-lux multi-site) keep their own
# ./app/lib/user_session.rb; the guard below defers to it (the app autoloader
# only fires on an undefined constant).

module UserSession
  extend self
  extend Lux::Application::Shared

  USER_REF      = :user_ref
  SUDO_USER_REF = :sudo_user_ref

  def resolve
    if bearer = current.bearer_token
      resolve_bearer bearer
    elsif token = params[:sso_action]
      resolve_sso_action token
    elsif params[:uref] && Lux.env.dev?
      uref = params[:uref]
      ref  = uref.include?('@') ? User.find_by(email: uref)&.ref : uref
      login_user_ref ref if ref
      redirect_to request.path
    elsif ref = session_ref
      load_user_by_ref ref
    end
  end

  # login magic link (mailers, cross-host, dev/admin login-as).
  # subdomain: builds an absolute link on that subdomain of the current host.
  def login_link user, path: nil, ttl: nil, subdomain: nil
    ref   = user.is_a?(String) ? user : user.ref
    token = sso_action_token(:login, ref: ref, ttl: ttl || 1.hour)

    return '%s?sso_action=%s' % [path || '/', token] unless subdomain

    Lux.current.url.subdomain(subdomain).path(path || '/').qs('sso_action', token).url
  end

  # absolute cross-subdomain link for the current user: auto-login token when
  # signed in, plain navigation link when User.current is nil.
  def transfer_link path = nil, subdomain:
    if user = User.current
      login_link user, path: path, subdomain: subdomain
    else
      Lux.current.url.subdomain(subdomain).path(path || '/').url
    end
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
    %[<div style="background:#c0392b;color:#fff;font:13px/1.4 sans-serif;padding:6px 12px;text-align:center;">] +
      %[Sudo as <b>#{label}</b> &middot; ] +
      %[<a href="?sso_action=false" style="color:#fff;text-decoration:underline;">sudo off</a></div>]
  end

  def login_user_ref ref
    session[USER_REF] = ref
    load_user_by_ref ref
  end

  def destroy_session
    session.delete USER_REF
    session.delete SUDO_USER_REF
    User.current = nil
  end

  def redirect_after_login= location
    session[:redirect_after_login] = location
  end

  def redirect_after_login! where = nil
    if location = session.delete(:redirect_after_login)
      redirect_to location
    elsif where
      redirect_to where
    else
      false
    end
  end

  private

  # encode the ?sso_action= token: { action:, ... } encrypted with a TTL
  def sso_action_token action, ttl:, **data
    Lux::Utils::Crypt.encrypt({ action: action }.merge(data), ttl: ttl)
  end

  # decrypt ?sso_action= and dispatch to action_<name>
  def resolve_sso_action token
    return action_sudo_off if token == 'false'

    data = Lux::Utils::Crypt.decrypt(token, unsafe: true) or return
    case data['action']
    when 'login'   then action_login   data
    when 'sudo_as' then action_sudo_as data
    when 'logout'  then action_logout  data
    end
  end

  def action_login data
    user = User.take(data['ref']) or return redirect_to('/', error: 'User cant be loaded')
    session[USER_REF] = user.ref
    User.current = user
    redirect_to request.path, info: 'Loged in as %s' % user.email
  end

  def action_sudo_as data
    return unless (User.current && User.current.can.admin?) || Lux.env.dev?
    target = User.take(data['ref'])
    if target && User.current && target.ref != User.current.ref
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
    return base if base && sudo && Lux.current.nav.path.first == 'admin'
    sudo || base
  end

  def resolve_bearer bearer
    if Lux.env.dev? && bearer.include?('@')
      User.current = User.find_by(email: bearer)
    elsif User.columns.include?(:api_key)
      Lux.logger.error "Bad bearer token: #{bearer}" unless User.current = User.find_by(api_key: bearer)
    end
  end

  def load_user_by_ref ref
    User.current = User.take(ref)
    current.can_clear_cache ||= true if User.current && (Lux.env.dev? || User.current.can.admin?)
  end

  def resolve_redirect info = nil
    if session[USER_REF]
      redirect_to session.delete(:redirect_after_login) || request.path, info: info
    else
      redirect_to '/', error: 'Session ended, please login again'
    end
  end
end
