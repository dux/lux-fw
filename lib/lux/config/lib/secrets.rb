# edit ./tmp/secrets.yaml and just reload lux

require 'yaml'

class Lux::Config::Secrets
  attr_reader :read_file, :secret_file, :secret, :strength

  def initialize
    @read_file   = Pathname.new './tmp/secrets.yaml'
    @secret_file = Pathname.new './config/secrets.enc'
    @secret      = ENV['SECRET_KEY_BASE'] || ENV.fetch('SECRET')
    @strength    = 'HS512'
  end

  def to_h
    it   = JWT.decode(@secret_file.read, @secret, true, { algorithm: @strength }).first
    it   = YAML.load it
    data = it['shared'] || {}

    data.merge(it[Lux.env] || {})
  end

  def load
    data = to_h

    for k in data.keys
      data[k] = data[k].to_struct if data[k].class == Hash
    end

    # DynamicClass.new data
    data.to_struct('LuxSecrets')
  end

end