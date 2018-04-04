# https://console.developers.google.com
# https://developers.google.com/identity/protocols/googlescopes

class LuxOauth::Google < LuxOauth
  def scope
    [
      'https://www.googleapis.com/auth/userinfo.email',
      'https://www.googleapis.com/auth/userinfo.profile'
    ]
  end

  def format_response opts
    {
      email:  opts['email'],
      name:   opts['name'],
      avatar: opts['picture'],
      locale: opts['locale'],
      gender: opts['gender']
    }
  end

  def login
    "https://accounts.google.com/o/oauth2/auth?client_id=#{@key}&redirect_uri=#{redirect_url}&scope=#{scope.join('%20')}&response_type=code"
  end

  def callback(session_code)
    result = RestClient.post('https://www.googleapis.com/oauth2/v3/token', {
      grant_type:    'authorization_code',
      client_id:     @key,
      client_secret: @secret,
      code:          session_code,
      redirect_uri:  redirect_url
    })

    hash = JSON.parse(result)

    user = JSON.parse RestClient.get('https://www.googleapis.com/oauth2/v1/userinfo', { :params => {:access_token => hash['access_token'], :alt=>:json }})

    format_response user
  end
end
