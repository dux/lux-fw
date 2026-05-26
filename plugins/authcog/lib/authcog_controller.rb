# Central-auth landing for AuthCog. Browser is redirected here by the central
# auth host after a successful login:
#
#   GET /authcog?callback=<40-char-hash>
#
# We server-side exchange the hash for { email, name, avatar, provider } at
# Lux.config.authcog (the central-auth exchange URL) and sign the user in.

class AuthcogController < Lux::Controller
  def call
    callback = params[:callback].to_s
    raise Lux.error.bad_request('Missing callback') unless callback =~ /\A[A-Za-z0-9]{40}\z/

    data = fetch_identity(callback)
    raise Lux.error.bad_request("AuthCog returned no email") if data[:email].blank?

    Lux.logger(:authcog).info "central-auth login - #{data[:email]} (#{data[:provider]})"

    User.current = User.quick_create(data[:email])
    session[:user_ref] = user.ref

    if user.is_locked
      return redirect_to '/', error: 'You are locked and you are not allowed to log in.'
    end

    user.name ||= data[:name]
    user.is_deleted = false
    user.save

    if data[:avatar] && user.cached_avatar.blank?
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

  def fetch_identity callback
    uri = URI("#{Lux.config.authcog}?user=#{callback}")
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
