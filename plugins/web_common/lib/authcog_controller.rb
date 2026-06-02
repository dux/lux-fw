# Central-auth callback landing for AuthCog. A single controller, mapped once
# at /authcog, exchanges callback hashes for local sessions:
#
#   GET /authcog?callback=<hash>  -> exchange the hash and sign the user in
#
# Central auth sends the browser back to /authcog?callback=<40-char-hash>; we
# exchange it server-side at https://auth.authcog.com/domain:<host> for
# { email, name, avatar, provider } and start a local session.
#
# Wire up in routes.rb:
#   map 'authcog', 'authcog#call'

class AuthcogController < Lux::Controller
  def self.auth_link here = Url.current
    path = "/domain:#{here.host}"
    path += "/port:#{here.port}" if here.port

    "https://auth.authcog.com#{path}"
  end

  def call
    action :callback
  end

  # GET /authcog?callback=<hash> - exchange the single-use hash and sign in.
  def callback
    callback_hash = params[:callback].to_s
    raise Lux.error.bad_request('Missing callback') unless callback_hash =~ /\A[A-Za-z0-9]{40}\z/

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

    if data[:avatar] && user.respond_to?(:cached_avatar) && user.cached_avatar.blank?
      avatar = data[:avatar]
      Lux.current.defer do
        uploaded = Cdn.upload_hash(avatar, path: 'avatars/users') rescue avatar
        user[:cached_avatar] = uploaded
        user.save
      end
    end

    target = session.delete(:redirect_after_login) || '/'
    redirect_to "#{target}?login=authcog"
  end

  private

  def user
    User.current
  end

  def fetch_identity callback_hash
    # Exchange is scoped to the relying domain: central auth only releases the
    # hash to the same host it was issued for (this request's own host).
    uri = URI("#{self.class.auth_link}?user=#{callback_hash}")
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
