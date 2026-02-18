# https://api.stackexchange.com/docs/authentication

class LuxOauth::Stackexchange < LuxOauth
  def initialize
    raise ArgumentError.new('OAUTH_ID needed') unless @opts.id
  end

  def login
    'https://stackexchange.com/oauth?client_id=%d&redirect_uri=%s' % [@opts.id, CGI::escape(redirect_url)]
  end

  def format_response opts
    {
      stackexchange_user_id: opts['items'].first['user_id'],
      user: opts['items'].first
    }
  end

  def callback session_code
    result = RestClient.post('https://stackexchange.com/oauth/access_token', {
      redirect_uri:  redirect_url,
      client_id:     @opts.id,
      client_secret: @opts.secret,
      code:          session_code
    }, { :accept => :json })

    access_token = result.to_s.qs_to_hash['access_token']

    response = RestClient.get('https://api.stackexchange.com/2.2/me', {
      accept: :json,
      params: {
        site: 'stackoverflow',
        access_token: access_token,
        key: @opts.key
      }
    })

    format_response JSON.parse response
  end
end

