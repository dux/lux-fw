# https://api.stackexchange.com/docs/authentication

class LuxOauth::Stackexchange < LuxOauth
  def login
    'https://stackexchange.com/oauth?client_id=%d&redirect_uri=%s' % [ENV.fetch('STACKEXCHANGE_OAUTH_ID'), CGI::escape(redirect_url)]
  end

  def format_response
    {
      stackexchnage_user_id: opts['items'].first['user_id'],
      user: opts['items'].first
    }
  end

  def callback session_code
    result = RestClient.post('https://stackexchange.com/oauth/access_token', {
      redirect_uri:  redirect_url,
      client_id:     ENV.fetch('STACKEXCHANGE_OAUTH_ID'),
      client_secret: @secret,
      code:          session_code
    }, { :accept => :json })

    access_token = result.to_s.css_to_hash['access_token']

    response = RestClient.get('https://api.stackexchange.com/2.2/me', {
      accept: :json,
      params: {
        site: 'stackoverflow',
        access_token: access_token,
        key: @key
      }
    })

    format_response JSON.parse response
  end
end

