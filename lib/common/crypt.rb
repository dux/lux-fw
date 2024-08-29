# frozen_string_literal: true

# @author: Dino Reic
# @description:
#   module for easy and convenient access to frequently used crypt operations

require 'openssl'
require 'base64'
require 'digest/md5'
require 'securerandom'

module Crypt
  extend self

  ALGORITHM = 'HS512'

  def secret
    ENV.fetch('SECRET') { Lux.config.secret } || die('Lux.config.secret not set')
  end

  def base64 str
    Base64.urlsafe_encode64(str)
  end

  def uid size = nil
    # there is also StringBase.uid
    SecureRandom.alphanumeric(size || 32).downcase
  end

  def sha1 str
    Digest::SHA1.hexdigest(str.to_s + secret)
  end

  # sha1 shorter string
  def sha1s str
    Integer(Digest::SHA1.hexdigest(str.to_s), 16).to_s(36)
  end

  def md5 str
    Digest::MD5.hexdigest(str.to_s + secret)
  end

  def random length=32
    chars = 'abcdefghjkmnpqrstuvwxyz0123456789'
    length
      .times
      .inject([]) { |t, _| t.push chars[rand(chars.size)] }
      .join('')
  end

  def bcrypt plain, check = nil
    if check
      BCrypt::Password.new(check) == [plain, secret].join('')
    else
      BCrypt::Password.create(plain + secret)
    end
  end

  # Crypt.encrypt('secret')
  # Crypt.encrypt('secret', ttl:1.hour, password:'pa$$w0rd')
  def encrypt data, opts = {}
    opts          = opts.to_hwia :ttl, :password
    payload       = { data:data }
    payload[:ttl] = Time.now.to_i + opts.ttl.to_i if opts.ttl

    JWT.encode payload, secret+opts.password.to_s, ALGORITHM
  end

  # Crypt.decrypt('secret')
  # Crypt.decrypt('secret', password:'pa$$w0rd', unsafe: true)
  def decrypt token, opts={}
    opts = opts.to_hwia :password, :ttl

    token_data = JWT.decode token, secret+opts.password.to_s, true, { algorithm: ALGORITHM }
    data = token_data[0]

    if data['ttl'] && data['ttl'] < Time.now.to_i
      seconds = Time.now.to_i - data['ttl']
      before  = Time.respond_to?(:ago) ? Time.ago(Time.now - seconds) : "#{seconds} seconds"
      raise JWT::VerificationError, "Crypted data expired before #{before}. Please get a fresh token."
    end

    data['data']
  rescue => err
    raise err unless opts[:unsafe]
  end

  # encrypts data, with unsafe base64 + basic check
  # not for sensitive data
  def short_encrypt data, ttl = nil
    # expires in one day by deafult
    ttl ||= 1.day
    ttl   = ttl.to_i + Time.now.to_i

    data  = [data, ttl].to_json
    sha1(data + Lux.config.secret)[0,8] + base64(data).sub(/=+$/, '')
  end

  def short_decrypt data
    check   = nil
    data    = data.sub(/^(.{8})/) { check = $1; ''}
    decoded = Base64.urlsafe_decode64(data)
    out     = JSON.load decoded

    raise ArgumentError.new('Invalid check') unless sha1(decoded + Lux.config.secret)[0,8] == check
    raise ArgumentError.new('Short code expired') if out[1] < Time.now.to_i

    out[0]
  end

  # works with Z.simpleEncode
  def simple_decode str
    Base64.decode64 str.gsub('_', '/').tr('A-Za-z', 'N-ZA-Mn-za-m')
  end

  def simple_encode str
    Base64.encode64(str).gsub('_', '/').tr('A-Za-z', 'N-ZA-Mn-za-m').gsub(/=+$/, '').gsub(/\s/, '')
  end
end
