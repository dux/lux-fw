# https://github.com/settings/developers
# https://github.com/github/platform-samples/tree/master/api/ruby/basics-of-authentication
# https://github.com/settings/applications

class LuxOauth::Github < LuxOauth
  def login
    "https://github.com/login/oauth/authorize?scope=user:email&client_id=#{@opts.key}"
  end

  def format_response opts
    {
      email:    opts['email'],
      avatar:   opts['avatar_url'],
      github:   opts['login'],
      company:  opts['company'],
      location: opts['location'],
      bio:      opts['description'],
      name:     opts['name']
    }
  end

  def callback session_code
    result = RestClient.post('https://github.com/login/oauth/access_token', {
      client_id:     @opts.key,
      client_secret: @opts.secret,
      code:          session_code
    }, { :accept => :json })

    # extract token and granted scopes
    access_token = JSON.parse(result)['access_token']
    # scopes = JSON.parse(result)['scope'].split(',')

    response = RestClient.get('https://api.github.com/user', {:params => {:access_token => access_token}, :accept => :json}).body

    Lux.logger(:oauth).info [:github, response]

    opts = JSON.parse(response)

    format_response opts
  end
end

