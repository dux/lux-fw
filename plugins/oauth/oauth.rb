class LuxOauth
  @@keys       = {}
  class_attribute :local_path, 'callback'

  class << self
    def register schema, opts={}
      opts = opts.to_h.h_wia

      for el in %i[key secret]
        raise ArgumentError.new('OAUTH %s needed for %s' % [el, schema]) unless opts[el]
      end

      raise ArgumentError.new('OAUTH_ID needed') if schema == :stackexchange && !opts[:id]

      @@keys[schema] = opts
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

    @full_host = full_host
    @key       = @@keys[@schema][:key]
    @secret    = @@keys[@schema][:secret]
    @id        = @@keys[@schema][:id]
  end

  def redirect_url
    [@full_host, self.class.local_path, @schema].join('/')
  end

end