# Shared browser session + admin "sudo as" support for web_common apps.
#
# Identity is keyed on user.ref. Magic links carry an encrypted ref in
# ?user_hash= (login) or ?sudo_as= (admin sudo); resolve() decrypts them on
# the next request. Links are plain URLs, so they work in mailers and across
# hosts. Sudo is an overlay: the target wins everywhere except /admin, where
# the real admin identity is kept.
#
# Apps with bespoke session logic (e.g. cms-lux multi-site) keep their own
# ./app/lib/user_session.rb; the guard below defers to it (the app autoloader
# only fires on an undefined constant).

unless File.exist?('./app/lib/user_session.rb')
  module UserSession
    extend self
    extend Lux::Application::Shared

    USER_REF      = :user_ref
    SUDO_USER_REF = :sudo_user_ref

    def resolve
      if bearer = current.bearer_token
        resolve_bearer bearer
      elsif params[:user_hash]
        login_user_hash params[:user_hash]
      elsif params[:uref] && Lux.env.dev?
        login_user_ref params[:uref]
        redirect_to request.path
      elsif params['login-as-guest'] && defined?(User::GUEST_EMAIL)
        login_user_ref User.find_by_email(User::GUEST_EMAIL).ref
        redirect_to request.path
      elsif params[:sudo_as]
        resolve_as_sudo params[:sudo_as]
      elsif ref = session_ref
        load_user_by_ref ref
      end
    end

    # login magic link (mailers, cross-host, dev/admin login-as)
    def login_link user, prefix = nil, ttl: nil
      ref = user.is_a?(String) ? user : user.ref
      '%s?user_hash=%s' % [prefix || '/', Lux::Utils::Crypt.encrypt(ref, ttl: ttl || 1.year)]
    end

    # admins only: start a sudo overlay
    def sudo_login_link user, path = nil
      '%s?sudo_as=%s' % [path || '/', Lux::Utils::Crypt.encrypt(user.ref, ttl: 1.hour)]
    end

    # dedicated logout URL; the /log-off route (authcog#log_off) verifies + ends the session
    def logout_link where = nil
      "/log-off?check=#{Lux::Utils::Crypt.short_encrypt(User.current.ref)}"
    end

    def sudo?
      session[SUDO_USER_REF].present?
    end
    alias_method :sudo_user?, :sudo?

    # Admin sudo banner: a thin red bar naming the impersonated user plus a
    # one-click "sudo off". Returns nil unless a sudo overlay is active, so a
    # layout can drop `= UserSession.sudo_bar` at the very top of %body and it
    # stays invisible for normal sessions. The link hits ?sudo_as=false, which
    # resolve() maps to clearing the overlay (see resolve_as_sudo).
    def sudo_bar
      return unless sudo?
      user  = User.take(session[SUDO_USER_REF]) or return
      label = ::Rack::Utils.escape_html(user.name.presence || user.email)
      %[<div style="background:#c0392b;color:#fff;font:13px/1.4 sans-serif;padding:6px 12px;text-align:center;">] +
        %[Sudo as <b>#{label}</b> &middot; ] +
        %[<a href="?sudo_as=false" style="color:#fff;text-decoration:underline;">sudo off</a></div>]
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

    # sudo overlay wins except under /admin (keep the real admin there)
    def session_ref
      base = session[USER_REF]
      sudo = session[SUDO_USER_REF]
      return base if base && sudo && Lux.current.nav.path.first == 'admin'
      sudo || base
    end

    def login_user_hash hash
      ref  = Lux::Utils::Crypt.decrypt(hash)
      user = User.take(ref) or return redirect_to('/', error: 'User cant be loaded')
      session[USER_REF] = user.ref
      User.current = user
      resolve_redirect(params[:silent] ? nil : 'User %s loaded' % user.email)
    rescue => err
      Lux.error.log err
      redirect_to '/', error: 'User can not be loaded'
    end

    def resolve_bearer bearer
      if Lux.env.dev? && bearer.include?('@')
        User.current = User.find_by(email: bearer)
      elsif User.columns.include?(:api_key)
        Lux.logger.error "Bad bearer token: #{bearer}" unless User.current = User.find_by(api_key: bearer)
      end
    end

    def resolve_as_sudo sudo_as
      if sudo_as == 'false'
        session.delete SUDO_USER_REF
        redirect_to request.path, info: 'Sudoing canceled'
      elsif (User.current && User.current.can.admin?) || Lux.env.dev?
        target = User.take(Lux::Utils::Crypt.decrypt(sudo_as))
        if target && User.current && target.ref != User.current.ref
          session[SUDO_USER_REF] = target.ref
          resolve_redirect 'Sudoing as %s' % target.name
        else
          response.flash.error 'Sudo error'
        end
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
end
