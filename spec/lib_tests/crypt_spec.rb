require 'test_helper'

describe Lux::Utils::Crypt do
  describe '.encrypt / .decrypt' do
    it 'encrypts and decrypts a simple string' do
      encrypted = Lux::Utils::Crypt.encrypt('abc')
      _(encrypted).must_be_kind_of String
      _(encrypted).wont_equal 'abc'
      _(Lux::Utils::Crypt.decrypt(encrypted)).must_equal 'abc'
    end

    it 'encrypts and decrypts complex data' do
      data = { 'users' => [1, 2, 3], 'name' => 'test' }
      encrypted = Lux::Utils::Crypt.encrypt(data)
      _(Lux::Utils::Crypt.decrypt(encrypted)).must_equal data
    end

    it 'encrypts with password and requires it for decryption' do
      encrypted = Lux::Utils::Crypt.encrypt('abc', password: 'foo')
      _{ Lux::Utils::Crypt.decrypt(encrypted) }.must_raise StandardError
      _(Lux::Utils::Crypt.decrypt(encrypted, password: 'foo')).must_equal 'abc'
    end

    it 'encrypts with TTL and rejects expired tokens' do
      future_str  = Lux::Utils::Crypt.encrypt('foo', ttl: 10)
      expired_str = Lux::Utils::Crypt.encrypt('foo', ttl: -10)

      _(Lux::Utils::Crypt.decrypt(future_str)).must_equal 'foo'
      _{ Lux::Utils::Crypt.decrypt(expired_str) }.must_raise StandardError
    end

    it 'returns nil for expired tokens with unsafe option' do
      expired = Lux::Utils::Crypt.encrypt('foo', ttl: -10)
      _(Lux::Utils::Crypt.decrypt(expired, unsafe: true)).must_be_nil
    end
  end

  describe '.sha1' do
    it 'returns a consistent hex digest' do
      result = Lux::Utils::Crypt.sha1('test')
      _(result).must_be_kind_of String
      _(result).must_match(/\A[0-9a-f]{40}\z/)
      _(Lux::Utils::Crypt.sha1('test')).must_equal result
    end

    it 'returns different digests for different inputs' do
      _(Lux::Utils::Crypt.sha1('a')).wont_equal Lux::Utils::Crypt.sha1('b')
    end
  end

  describe '.sha1s' do
    it 'returns a shorter base-36 digest' do
      result = Lux::Utils::Crypt.sha1s('test')
      _(result).must_be_kind_of String
      _(result).must_match(/\A[0-9a-z]+\z/)
    end
  end

  describe '.md5' do
    it 'returns a consistent hex digest' do
      result = Lux::Utils::Crypt.md5('test')
      _(result).must_be_kind_of String
      _(result).must_match(/\A[0-9a-f]{32}\z/)
      _(Lux::Utils::Crypt.md5('test')).must_equal result
    end

    it 'returns different digests for different inputs' do
      _(Lux::Utils::Crypt.md5('a')).wont_equal Lux::Utils::Crypt.md5('b')
    end
  end

  describe '.uid' do
    it 'returns a 32-char lowercase alphanumeric string by default' do
      uid = Lux::Utils::Crypt.uid
      _(uid.length).must_equal 32
      _(uid).must_match(/\A[a-z0-9]+\z/)
    end

    it 'returns a string of specified size' do
      uid = Lux::Utils::Crypt.uid(16)
      _(uid.length).must_equal 16
    end

    it 'generates unique values' do
      uids = 10.times.map { Lux::Utils::Crypt.uid }
      _(uids.uniq.length).must_equal 10
    end
  end

  describe '.random' do
    it 'returns a random string of given length' do
      result = Lux::Utils::Crypt.random(16)
      _(result.length).must_equal 16
      _(result).must_match(/\A[a-z0-9]+\z/)
    end

    it 'defaults to 32 characters' do
      _(Lux::Utils::Crypt.random.length).must_equal 32
    end
  end

  describe '.base64' do
    it 'returns url-safe base64 encoding' do
      result = Lux::Utils::Crypt.base64('hello world')
      _(result).must_be_kind_of String
      refute result.include?('+')
      refute result.include?('/')
    end
  end

  describe '.short_encrypt / .short_decrypt' do
    it 'encrypts and decrypts data with short tokens' do
      encrypted = Lux::Utils::Crypt.short_encrypt('secret_data')
      _(encrypted).must_be_kind_of String
      _(Lux::Utils::Crypt.short_decrypt(encrypted)).must_equal 'secret_data'
    end

    it 'rejects expired short tokens' do
      encrypted = Lux::Utils::Crypt.short_encrypt('secret_data', -10)
      err = _{ Lux::Utils::Crypt.short_decrypt(encrypted) }.must_raise ArgumentError
      _(err.message).must_match(/expired/)
    end

    it 'rejects tampered tokens' do
      encrypted = Lux::Utils::Crypt.short_encrypt('secret_data')
      tampered = 'XXXXXXXX' + encrypted[8..]
      err = _{ Lux::Utils::Crypt.short_decrypt(tampered) }.must_raise ArgumentError
      _(err.message).must_match(/Invalid check/)
    end
  end

  describe '.simple_encode / .simple_decode' do
    it 'encodes and decodes strings with ROT13+base64' do
      original = 'hello world'
      encoded = Lux::Utils::Crypt.simple_encode(original)
      _(encoded).wont_equal original
      _(Lux::Utils::Crypt.simple_decode(encoded)).must_equal original
    end
  end
end
