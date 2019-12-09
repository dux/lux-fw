# https://developer.linkedin.com/docs/oauth2
# https://developer.linkedin.com/docs/fields/basic-profile

class LuxOauth::Linkedin < LuxOauth
  def scope
    [
      # 'r_basicprofile',
      'r_liteprofile',
      'r_emailaddress'
    ]
  end

  def login
    "https://www.linkedin.com/oauth/v2/authorization?response_type=code&client_id=#{@opts.key}&redirect_uri=#{redirect_url}&state=987654321&scope=#{scope.join('%20')}"
  end

  def callback session_code
    result = RestClient.post('https://www.linkedin.com/oauth/v2/accessToken', {
      grant_type:    'authorization_code',
      client_id:     @opts.key,
      client_secret: @opts.secret,
      code:          session_code,
      redirect_uri:  redirect_url
    })

    out = {}

    @access_token = JSON.parse(result)['access_token']

    # basic data
    opts = api_call 'https://api.linkedin.com/v2/me'
    out[:name] = "#{opts['localizedFirstName']} #{opts['localizedLastName']}"

    # email
    opts = api_call 'https://api.linkedin.com/v2/clientAwareMemberHandles?q=members&projection=(elements*(primary,type,handle~))'
    out[:email] = opts['elements'][0]['handle~']['emailAddress']

    # image
    opts = api_call 'https://api.linkedin.com/v2/me?projection=(id,profilePicture(displayImage~:playableStreams))'
    out[:avatar] = opts['profilePicture']['displayImage~']['elements'][2]['identifiers'][0]['identifier'] rescue nil

    out
  end

  private

  def api_call url
    JSON.parse RestClient::Request.execute(:method=>:get, :url=>url, :headers => {'Authorization'=>"Bearer #{@access_token}"})
  end
end
