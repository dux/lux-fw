# frozen_string_literal: true

# @author: Dino Reic
# @description:
#   module for easy and convenient access to frequently used crypt operations

require 'openssl'
require 'base64'
require 'digest/md5'
require 'securerandom'

module Lux
module Utils
module Crypt
  extend self

  ALGORITHM ||= 'HS512'

  # sealed token layout: 12 byte iv + 16 byte GCM tag + ciphertext
  SEAL_HEAD ||= 28

  def secret
    ENV.fetch('SECRET') { Lux.config.secret } || raise('Lux.config.secret not set')
  end

  def base64 str
    Base64.urlsafe_encode64(str)
  end

  def uid size = nil
    # there is also StringBase.uid
    SecureRandom.alphanumeric(size || 32, chars: [*'a'..'z', *'0'..'9'])
  end

  # keyed digests: HMAC with the secret. A plain H(msg + secret) is no MAC, and
  # echoed anywhere (an ETag) it is an offline brute-force oracle for the secret.
  def sha1 str
    OpenSSL::HMAC.hexdigest('SHA1', secret, str.to_s)
  end

  # sha1 shorter string
  def sha1s str
    Integer(Digest::SHA1.hexdigest(str.to_s), 16).to_s(36)
  end

  def md5 str
    OpenSSL::HMAC.hexdigest('MD5', secret, str.to_s)
  end

  RANDOM_CHARS ||= 'abcdefghjkmnpqrstuvwxyz0123456789'
  def random length = 32
    Lux::Utils::StringBase.new(keys: RANDOM_CHARS).rand(length)
  end

  def bcrypt plain, check = nil
    require 'bcrypt'
    check ? BCrypt::Password.new(check) == plain.to_s + secret : BCrypt::Password.create(plain.to_s + secret)
  rescue LoadError
    raise LoadError, 'Lux.crypt.bcrypt needs the bcrypt gem in your Gemfile'
  end

  # Crypt.encrypt('secret')
  # Crypt.encrypt('secret', ttl:1.hour, password:'pa$$w0rd')
  def encrypt data, opts = {}
    opts          = opts.to_lux_hash :ttl, :password
    payload       = { data:data }
    payload[:exp] = Time.now.to_i + opts.ttl.to_i if opts.ttl

    JWT.encode payload, secret+opts.password.to_s, ALGORITHM
  end

  # Crypt.decrypt('secret')
  # Crypt.decrypt('secret', password:'pa$$w0rd', unsafe: true)
  # An expired token raises JWT::ExpiredSignature (JWT.decode checks `exp`).
  def decrypt token, opts={}
    opts = opts.to_lux_hash :password, :unsafe

    token_data = JWT.decode token, secret+opts.password.to_s, true, { algorithm: ALGORITHM }
    token_data[0]['data']
  rescue => err
    raise err unless opts[:unsafe]
  end

  # Authenticated encryption (AES-256-GCM). encrypt above is a signed JWT the
  # holder can read; a sealed token can be neither read nor altered. purpose
  # binds a token to one use, so a session cookie is not valid anywhere else.
  # Crypt.seal({ 'user_ref' => 'x' }, ttl: 1.day, purpose: 'session')
  def seal data, ttl: nil, purpose: 'lux'
    payload = { 'data' => data }
    payload['exp'] = Time.now.to_i + ttl.to_i if ttl

    cipher = OpenSSL::Cipher.new('aes-256-gcm').encrypt
    cipher.key = seal_key(purpose)
    iv = cipher.random_iv
    cipher.auth_data = purpose.to_s
    body = cipher.update(payload.to_json) + cipher.final

    Base64.urlsafe_encode64(iv + cipher.auth_tag + body, padding: false)
  end

  # nil when the token is forged, altered, sealed for another purpose or expired
  def unseal token, purpose: 'lux'
    raw = Base64.urlsafe_decode64(token.to_s)
    return if raw.bytesize <= SEAL_HEAD

    cipher = OpenSSL::Cipher.new('aes-256-gcm').decrypt
    cipher.key = seal_key(purpose)
    cipher.iv = raw[0, 12]
    cipher.auth_tag = raw[12, 16]
    cipher.auth_data = purpose.to_s
    payload = JSON.parse(cipher.update(raw[SEAL_HEAD..]) + cipher.final)

    payload['data'] unless payload['exp'] && payload['exp'] < Time.now.to_i
  rescue ArgumentError, OpenSSL::Cipher::CipherError, JSON::ParserError
    nil
  end

  # encrypts data, with unsafe base64 + basic check
  # not for sensitive data
  def short_encrypt data, ttl = nil
    payload = base64([data, Time.now.to_i + (ttl || 1.day).to_i].to_json).delete('=')
    short_mac(payload) + payload
  end

  def short_decrypt token
    token = token.to_s
    check, payload = token[0, 16], token[16..].to_s
    raise ArgumentError.new('Invalid check') unless Rack::Utils.secure_compare(short_mac(payload), check)
    out = JSON.parse Base64.urlsafe_decode64(payload)
    raise ArgumentError.new('Short code expired') if out[1] < Time.now.to_i
    out[0]
  end

  # works with Z.simpleEncode
  def simple_decode str
    Base64.decode64 str.gsub('_', '/').tr('A-Za-z', 'N-ZA-Mn-za-m')
  end

  def simple_encode str
    Base64.strict_encode64(str).tr('/', '_').delete('=').tr('A-Za-z', 'N-ZA-Mn-za-m')
  end

  private

  def seal_key purpose
    OpenSSL::KDF.hkdf(secret, salt: 'lux-seal', info: purpose.to_s, length: 32, hash: 'SHA256')
  end

  def short_mac payload
    OpenSSL::HMAC.hexdigest('SHA256', seal_key('short'), payload)[0, 16]
  end
end
end
end
