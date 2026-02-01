# https://developer.yahoo.com/apps/4IeDg7Xk/

class LuxOauth::Yahoo < LuxOauth
  def scope

  end

  def format_response opts
    {
      email:  opts['email'],
      name:   opts['name'],
      avatar: opts['picture'],
      locale: opts['locale'],
    }
  end

  def login
    "https://api.login.yahoo.com/oauth2/request_auth?client_id=#{@opts.key}&redirect_uri=#{redirect_url}&response_type=code&language=en-us"
  end

  def callback session_code
    uri = URI.parse("https://api.login.yahoo.com/oauth2/get_token")
    response = Net::HTTP.post_form(uri, {
      "client_id":     @opts.key,
      "client_secret": @opts.secret,
      "redirect_uri":  redirect_url,
      "code":          session_code,
      "grant_type":    "authorization_code"
    })

    response = RestClient::Request.execute({
      method: :get,
      url: "https://api.login.yahoo.com/openid/v1/userinfo",
      headers: {
        Authorization: "Bearer %s" % JSON.parse(response.body)['access_token']
      }
    })

    hash = JSON.parse(response)

    format_response hash
  end
end
