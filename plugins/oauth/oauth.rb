class LuxOauth
  class_attribute :local_path, 'callback'

  class << self
    def get target
      "LuxOauth::#{target.to_s.classify}".constantize.new
    end

    def login target
      get(target).login
    end
  end

  ###

  def initialize
    @target = self.class.to_s.split('::').last.downcase.to_sym
    @opts   = opts_loader

    raise ArgumentError, 'Host is invalid' unless host =~ /^https?:/

    for el in %i[key secret]
      raise ArgumentError.new('OAUTH %s needed for %s' % [el, @target]) unless @opts.send(el)
    end
  end

  def redirect_url
    [host, LuxOauth.local_path, @target].join('/')
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