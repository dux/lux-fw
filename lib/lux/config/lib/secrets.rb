# if you use encrypted secrets
# * edit ./tmp/secrets.yaml
# * increase version by 1
# * run "rake secrets" to encrypt secrets to ./config/secrets.enc

# if you use unprotected secrets in ./config/secrets.yaml
# * edit the file, no other actions needed

require 'yaml'

class Lux::Config::Secrets
  attr_reader :read_file, :secret_file, :secret, :strength

  def initialize
    @read_file   = Pathname.new './tmp/secrets.yaml'
    @secret_file = Pathname.new './config/secrets.enc'
    @common_file = Pathname.new './config/secrets.yaml'
    @secret      = Lux.config.secret_key_base || Lux.config.secret || ENV['SECRET'] || die('ENV SECRET not found')
    @strength    = 'HS512'
  end

  def write
    encoded = JWT.encode @read_file.read, @secret, @strength
    @secret_file.write encoded
  end

  def encoded_data
    JWT.decode(@secret_file.read, @secret, true, { algorithm: @strength }).first
  end

  def to_h
    it = if @common_file.exist?
      @common_file.read
    else
      encoded_data
    end

    it   = YAML.load it
    data = it['shared'] || {}

    data.merge(it[Lux.env] || {})
  end

  def load
    to_h.to_readonly
  end

end