# edit ./tmp/secrets.yaml and just reload lux

require 'yaml'

class Lux::Config::Secrets
  attr_reader :read_file, :secret_file, :secret, :strength

  def initialize
    @read_file   = Pathname.new './tmp/secrets.yaml'
    @secret_file = Pathname.new './config/secrets.enc'
    @secret      = Lux.config.secret_key_base || Lux.config.secret || ENV['SECRET'] || die('ENV SECRET not found')
    @strength    = 'HS512'
  end

  def to_h
    it   = JWT.decode(@secret_file.read, @secret, true, { algorithm: @strength }).first
    it   = YAML.load it
    data = it['shared'] || {}

    data.merge(it[Lux.env] || {})
  end

  def load
    to_h.to_struct
  end

end