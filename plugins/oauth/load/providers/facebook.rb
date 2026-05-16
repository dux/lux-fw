# https://developers.facebook.com
# https://developers.facebook.com/docs/facebook-login/manually-build-a-login-flow

class LuxOauth::Facebook < LuxOauth
  def login
    'https://www.facebook.com/v2.8/dialog/oauth?scope=email&client_id=%s&redirect_uri=%s' % [@opts.key, CGI::escape(redirect_url)]
  end

  def format_response opts
    {
      email:    opts['email'],
      avatar:   '//graph.facebook.com/%s/picture?type=large' % opts['id'],
      name:     opts['name']
    }
  end

  def callback session_code
    result = RestClient.post('https://graph.facebook.com/v2.8/oauth/access_token', {
      redirect_uri:  redirect_url,
      client_id:     @opts.key,
      client_secret: @opts.secret,
      code:          session_code
    }, { :accept => :json })

    access_token = JSON.parse(result)['access_token']

    response = RestClient.get('https://graph.facebook.com/me', {
      :accept => :json,
      :params => { :access_token => access_token }
    })

    format_response JSON.parse response
  end
end

