class LuxOauth
  cattr.local_path = 'callback'

  class << self
    def get target
      "LuxOauth::#{target.to_s.classify}".constantize.new
    end

    def login target, state: nil
      get(target).login_url(state: state)
    end
  end

  ###

  # Authorization URL carrying an anti-forgery `state`. Providers only build
  # their own base URL in #login, so the nonce is appended here once instead of
  # in every provider. The caller stores it and re-checks it on the callback.
  def login_url state: nil
    url = login
    return url if state.to_s.empty?

    "#{url}#{url.include?('?') ? '&' : '?'}state=#{Url.escape(state)}"
  end

  def initialize
    @target = self.class.to_s.split('::').last.downcase.to_sym
    @opts   = opts_loader

    raise ArgumentError, 'Host is invalid' unless host =~ /^https?:/

    for el in %i[key secret]
      raise ArgumentError.new('OAUTH %s needed for %s' % [el, @target]) unless @opts.send(el)
    end
  end

  def redirect_url
    [host, cattr.local_path, @target].join('/')
  end

  private

  def opts_loader
    Lux.secrets.send(@target).oauth
  rescue
    raise "Can't load Oauth secrets for #{@target}: #{$!.message}"
  end

  def host
    Lux.config.host
  end
end