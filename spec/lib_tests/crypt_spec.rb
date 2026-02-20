require 'spec_helper'

describe Crypt do
  describe '.encrypt / .decrypt' do
    it 'encrypts and decrypts a simple string' do
      encrypted = Crypt.encrypt('abc')
      expect(encrypted).to be_a(String)
      expect(encrypted).not_to eq('abc')
      expect(Crypt.decrypt(encrypted)).to eq('abc')
    end

    it 'encrypts and decrypts complex data' do
      data = { 'users' => [1, 2, 3], 'name' => 'test' }
      encrypted = Crypt.encrypt(data)
      expect(Crypt.decrypt(encrypted)).to eq(data)
    end

    it 'encrypts with password and requires it for decryption' do
      encrypted = Crypt.encrypt('abc', password: 'foo')
      expect { Crypt.decrypt(encrypted) }.to raise_error(StandardError)
      expect(Crypt.decrypt(encrypted, password: 'foo')).to eq('abc')
    end

    it 'encrypts with TTL and rejects expired tokens' do
      future_str  = Crypt.encrypt('foo', ttl: 10)
      expired_str = Crypt.encrypt('foo', ttl: -10)

      expect(Crypt.decrypt(future_str)).to eq('foo')
      expect { Crypt.decrypt(expired_str) }.to raise_error(StandardError)
    end

    it 'returns nil for expired tokens with unsafe option' do
      expired = Crypt.encrypt('foo', ttl: -10)
      expect(Crypt.decrypt(expired, unsafe: true)).to be_nil
    end
  end

  describe '.sha1' do
    it 'returns a consistent hex digest' do
      result = Crypt.sha1('test')
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-f]{40}\z/)
      expect(Crypt.sha1('test')).to eq(result)
    end

    it 'returns different digests for different inputs' do
      expect(Crypt.sha1('a')).not_to eq(Crypt.sha1('b'))
    end
  end

  describe '.sha1s' do
    it 'returns a shorter base-36 digest' do
      result = Crypt.sha1s('test')
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-z]+\z/)
    end
  end

  describe '.md5' do
    it 'returns a consistent hex digest' do
      result = Crypt.md5('test')
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-f]{32}\z/)
      expect(Crypt.md5('test')).to eq(result)
    end

    it 'returns different digests for different inputs' do
      expect(Crypt.md5('a')).not_to eq(Crypt.md5('b'))
    end
  end

  describe '.uid' do
    it 'returns a 32-char lowercase alphanumeric string by default' do
      uid = Crypt.uid
      expect(uid.length).to eq(32)
      expect(uid).to match(/\A[a-z0-9]+\z/)
    end

    it 'returns a string of specified size' do
      uid = Crypt.uid(16)
      expect(uid.length).to eq(16)
    end

    it 'generates unique values' do
      uids = 10.times.map { Crypt.uid }
      expect(uids.uniq.length).to eq(10)
    end
  end

  describe '.random' do
    it 'returns a random string of given length' do
      result = Crypt.random(16)
      expect(result.length).to eq(16)
      expect(result).to match(/\A[a-z0-9]+\z/)
    end

    it 'defaults to 32 characters' do
      expect(Crypt.random.length).to eq(32)
    end
  end

  describe '.base64' do
    it 'returns url-safe base64 encoding' do
      result = Crypt.base64('hello world')
      expect(result).to be_a(String)
      expect(result).not_to include('+', '/')
    end
  end

  describe '.short_encrypt / .short_decrypt' do
    it 'encrypts and decrypts data with short tokens' do
      encrypted = Crypt.short_encrypt('secret_data')
      expect(encrypted).to be_a(String)
      expect(Crypt.short_decrypt(encrypted)).to eq('secret_data')
    end

    it 'rejects expired short tokens' do
      encrypted = Crypt.short_encrypt('secret_data', -10)
      expect { Crypt.short_decrypt(encrypted) }.to raise_error(ArgumentError, /expired/)
    end

    it 'rejects tampered tokens' do
      encrypted = Crypt.short_encrypt('secret_data')
      tampered = 'XXXXXXXX' + encrypted[8..]
      expect { Crypt.short_decrypt(tampered) }.to raise_error(ArgumentError, /Invalid check/)
    end
  end

  describe '.simple_encode / .simple_decode' do
    it 'encodes and decodes strings with ROT13+base64' do
      original = 'hello world'
      encoded = Crypt.simple_encode(original)
      expect(encoded).not_to eq(original)
      expect(Crypt.simple_decode(encoded)).to eq(original)
    end
  end
end