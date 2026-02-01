# https://api.slack.com/

class LuxOauth::Slack < LuxOauth
  def login
    redirect_uri = Url.escape '%s/callback/slack' % Lux.config.host
    'https://slack.com/oauth/authorize?scope=identity.basic,identity.email,identity.avatar&client_id=%s&redirect_uri=%s' % [@opts.key, redirect_uri]
  end

  def format_response opts
    {
      name: opts['user']['name'],
      email: opts['user']['email'],
      avatar: opts['user']['image_72']
    }
  end

  def callback session_code
    result = RestClient.post('https://slack.com/api/oauth.access', {
      client_id:     @opts.key,
      client_secret: @opts.secret,
      code:          session_code
    }, { :accept => :json })

    Lux.logger(:oauth).info [:slack, result.to_s]

    opts = JSON.parse result.to_s

    if opts['error']
      raise 'Login error: ' + opts['error']
    else
      # # extract token and granted scopes
      # access_token = JSON.parse(result)['access_token']

      # opts = JSON.parse(RestClient.get('https://api.github.com/user', {:params => {:access_token => access_token}, :accept => :json}))

      format_response opts
    end
  end
end

