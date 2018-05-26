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
    Lux.config.secret || die('ENV SECRET not set')
  end

  def base64 str
    Base64.urlsafe_encode64(str)
  end

  def uid
    SecureRandom.hex
  end

  def sha1 str
    Digest::SHA1.hexdigest(str.to_s + secret)
  end

  def md5 str
    Digest::MD5.hexdigest(str.to_s + secret)
  end

  def bcrypt plain, check=nil
    if check
      BCrypt::Password.new(check) == [plain, secret].join('')
    else
      BCrypt::Password.create(plain + secret)
    end
  end

  # Crypt.encrypt('secret')
  # Crypt.encrypt('secret', ttl:1.hour, password:'pa$$w0rd')
  def encrypt(data, opts={})
    opts = opts.to_opts!(:ttl, :password)

    payload = { data:data }
    payload[:ttl] = Time.now.to_i + opts.ttl if opts.ttl
    JWT.encode payload, secret+opts.password.to_s, ALGORITHM
  end

  # Crypt.decrypt('secret')
  # Crypt.decrypt('secret', password:'pa$$w0rd')
  def decrypt(token, opts={})
    opts = opts.to_opts!(:password)

    token_data = JWT.decode token, secret+opts.password.to_s, true, { :algorithm => ALGORITHM }
    data = token_data[0]
    raise "Crypted data expired before #{Time.now.to_i - data.ttl} seconds" if data['ttl'] && data['ttl'] < Time.now.to_i
    data['data']
  end

end
