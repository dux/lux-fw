require 'spec_helper'

describe Lux::Crypt do
  describe '.encrypt / .decrypt' do
    it 'encrypts and decrypts a simple string' do
      encrypted = Lux::Crypt.encrypt('abc')
      expect(encrypted).to be_a(String)
      expect(encrypted).not_to eq('abc')
      expect(Lux::Crypt.decrypt(encrypted)).to eq('abc')
    end

    it 'encrypts and decrypts complex data' do
      data = { 'users' => [1, 2, 3], 'name' => 'test' }
      encrypted = Lux::Crypt.encrypt(data)
      expect(Lux::Crypt.decrypt(encrypted)).to eq(data)
    end

    it 'encrypts with password and requires it for decryption' do
      encrypted = Lux::Crypt.encrypt('abc', password: 'foo')
      expect { Lux::Crypt.decrypt(encrypted) }.to raise_error(StandardError)
      expect(Lux::Crypt.decrypt(encrypted, password: 'foo')).to eq('abc')
    end

    it 'encrypts with TTL and rejects expired tokens' do
      future_str  = Lux::Crypt.encrypt('foo', ttl: 10)
      expired_str = Lux::Crypt.encrypt('foo', ttl: -10)

      expect(Lux::Crypt.decrypt(future_str)).to eq('foo')
      expect { Lux::Crypt.decrypt(expired_str) }.to raise_error(StandardError)
    end

    it 'returns nil for expired tokens with unsafe option' do
      expired = Lux::Crypt.encrypt('foo', ttl: -10)
      expect(Lux::Crypt.decrypt(expired, unsafe: true)).to be_nil
    end
  end

  describe '.sha1' do
    it 'returns a consistent hex digest' do
      result = Lux::Crypt.sha1('test')
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-f]{40}\z/)
      expect(Lux::Crypt.sha1('test')).to eq(result)
    end

    it 'returns different digests for different inputs' do
      expect(Lux::Crypt.sha1('a')).not_to eq(Lux::Crypt.sha1('b'))
    end
  end

  describe '.sha1s' do
    it 'returns a shorter base-36 digest' do
      result = Lux::Crypt.sha1s('test')
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-z]+\z/)
    end
  end

  describe '.md5' do
    it 'returns a consistent hex digest' do
      result = Lux::Crypt.md5('test')
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-f]{32}\z/)
      expect(Lux::Crypt.md5('test')).to eq(result)
    end

    it 'returns different digests for different inputs' do
      expect(Lux::Crypt.md5('a')).not_to eq(Lux::Crypt.md5('b'))
    end
  end

  describe '.uid' do
    it 'returns a 32-char lowercase alphanumeric string by default' do
      uid = Lux::Crypt.uid
      expect(uid.length).to eq(32)
      expect(uid).to match(/\A[a-z0-9]+\z/)
    end

    it 'returns a string of specified size' do
      uid = Lux::Crypt.uid(16)
      expect(uid.length).to eq(16)
    end

    it 'generates unique values' do
      uids = 10.times.map { Lux::Crypt.uid }
      expect(uids.uniq.length).to eq(10)
    end
  end

  describe '.random' do
    it 'returns a random string of given length' do
      result = Lux::Crypt.random(16)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[a-z0-9]+\z/)
    end

    it 'defaults to 32 characters' do
      expect(Lux::Crypt.random.length).to eq(32)
    end
  end

  describe '.base64' do
    it 'returns url-safe base64 encoding' do
      result = Lux::Crypt.base64('hello world')
      expect(result).to be_a(String)
      expect(result).not_to include('+', '/')
    end
  end

  describe '.short_encrypt / .short_decrypt' do
    it 'encrypts and decrypts data with short tokens' do
      encrypted = Lux::Crypt.short_encrypt('secret_data')
      expect(encrypted).to be_a(String)
      expect(Lux::Crypt.short_decrypt(encrypted)).to eq('secret_data')
    end

    it 'rejects expired short tokens' do
      encrypted = Lux::Crypt.short_encrypt('secret_data', -10)
      expect { Lux::Crypt.short_decrypt(encrypted) }.to raise_error(ArgumentError, /expired/)
    end

    it 'rejects tampered tokens' do
      encrypted = Lux::Crypt.short_encrypt('secret_data')
      tampered = 'XXXXXXXX' + encrypted[8..]
      expect { Lux::Crypt.short_decrypt(tampered) }.to raise_error(ArgumentError, /Invalid check/)
    end
  end

  describe '.simple_encode / .simple_decode' do
    it 'encodes and decodes strings with ROT13+base64' do
      original = 'hello world'
      encoded = Lux::Crypt.simple_encode(original)
      expect(encoded).not_to eq(original)
      expect(Lux::Crypt.simple_decode(encoded)).to eq(original)
    end
  end
end