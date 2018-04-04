class LuxOauth
  @@keys       = {}
  @@local_path = 'callback'

  class << self
    # LuxOauth.register :google, ENV.fetch('GOOGLE_OAUTH_KEY'), ENV.fetch('GOOGLE_OAUTH_SECRET')
    def register schema, client_key=nil, client_secret=nil
      client_key     ||= ENV["#{schema.to_s.upcase}_OAUTH_KEY"]    || raise('Oauth :%s key not defined' % schema)
      client_secret  ||= ENV["#{schema.to_s.upcase}_OAUTH_SECRET"] || raise('Oauth :%s secret not defined' % schema)

      @@keys[schema] = {}
      @@keys[schema][:key]    = client_key
      @@keys[schema][:secret] = client_secret
    end

    def local_path= value
      @@local_path = value
    end

    def get scheme, full_host
      "LuxOauth::#{scheme.to_s.classify}".constantize.new full_host
    end
  end

  ###

  def initialize full_host
    schema = self.class.to_s.split('::').last.downcase

    raise ArgumentError, 'Host is invalid: %s' % full_host.to_s unless full_host.to_s =~ /^https?:/
    @schema = schema.to_sym

    raise "Oauth config :#{schema} is not registred"  unless @@keys[@schema]
    raise "Oauth config :#{schema} is missing key"    unless @@keys[@schema][:key]
    raise "Oauth config :#{schema} is missing secret" unless @@keys[@schema][:secret]

    @full_host = full_host
    @key       = @@keys[@schema][:key]
    @secret    = @@keys[@schema][:secret]
  end

  def redirect_url
    [@full_host, @@local_path, @schema].join('/')
  end

end