# https://developer.twitter.com/en/docs/authentication/guides/log-in-with-twitter#item1
# POST https://api.twitter.com/oauth/request_token

class LuxOauth::Twitter < LuxOauth
  # def scope
  #   [
  #     'r_basicprofile',
  #     'r_emailaddress'
  #   ]
  # end

  # def login
  #   'https://api.twitter.com/oauth/authorize?oauth_token=%s' % @opts.key
  # end

  # def format_response opts
  #   {
  #     email:       opts['emailAddress'],
  #     linkedin:    opts['publicProfileUrl'],
  #     description: opts['specialties'],
  #     location:    opts['location'],
  #     avatar:      opts['pictureUrl'],
  #     name:        "#{opts['firstName']} #{opts['lastName']}"
  #   }
  # end

  # def callback(session_code)
  #   result = RestClient.post('https://www.linkedin.com/oauth/v2/accessToken', {
  #     grant_type:    'authorization_code',
  #     client_id:     @opts.key,
  #     client_secret: @opts.secret,
  #     code:          session_code,
  #     redirect_uri:  redirect_url
  #   })

  #   access_token = JSON.parse(result)['access_token']
  #   opts = JSON.parse RestClient::Request.execute(:method=>:get, :url=>'https://api.linkedin.com/v1/people/~:(id,picture-url,first-name,last-name,email-address,public-profile-url,specialties,location)?format=json', :headers => {'Authorization'=>"Bearer #{access_token}"})

  #   format_response opts
  # end
end
