require 'spec_helper'

describe StringBase do
  describe '.encode / .decode (short keys)' do
    it 'encodes and decodes integers' do
      encoded = StringBase.encode(12345)
      expect(encoded).to be_a(String)
      expect(StringBase.decode(encoded)).to eq(12345)
    end

    it 'encodes and decodes zero' do
      expect(StringBase.encode(0)).to eq('')
      # decode of empty string should return 0
      expect(StringBase.decode('')).to eq(0)
    end

    it 'handles large integers' do
      large = 999_999_999
      encoded = StringBase.encode(large)
      expect(StringBase.decode(encoded)).to eq(large)
    end
  end

  describe '.short' do
    let(:encoder) { StringBase.short }

    it 'uses SHORT_KEYS and multiplier 99' do
      encoded = encoder.encode(100)
      expect(encoder.decode(encoded)).to eq(100)
    end

    it 'rejects invalid base on decode' do
      # 'c' decodes to index 1, which is not divisible by multiplier 99
      expect { encoder.decode('c') }.to raise_error(RuntimeError, /Invalid decode base/)
    end
  end

  describe '.medium' do
    let(:encoder) { StringBase.medium }

    it 'encodes and decodes with medium keys' do
      encoded = encoder.encode(42)
      expect(encoder.decode(encoded)).to eq(42)
    end
  end

  describe '.long' do
    let(:encoder) { StringBase.long }

    it 'encodes and decodes with long keys (case-sensitive)' do
      encoded = encoder.encode(1000)
      expect(encoder.decode(encoded)).to eq(1000)
    end

    it 'produces shorter strings than medium for same value' do
      value = 100_000
      long_str = StringBase.long.encode(value)
      medium_str = StringBase.medium.encode(value)
      expect(long_str.length).to be <= medium_str.length
    end
  end

  describe '.uid' do
    it 'returns a 16-char string' do
      uid = StringBase.uid
      expect(uid).to be_a(String)
      expect(uid.length).to eq(16)
    end

    it 'generates unique values' do
      uids = 10.times.map { StringBase.uid; sleep(0.001); StringBase.uid }
      expect(uids.uniq.length).to be > 1
    end
  end

  describe '#rand' do
    it 'returns a random string of given length from key chars' do
      result = StringBase.medium.rand(10)
      expect(result.length).to eq(10)
      expect(result.chars).to all(match(/[a-z0-9]/))
    end
  end

  describe '#extract' do
    it 'extracts ID from a URL-style slug' do
      id = 42
      slug = "some-title-#{StringBase.encode(id)}"
      extracted = StringBase.short.extract(slug)
      expect(extracted).to eq(id)
    end

    it 'returns nil for invalid slugs' do
      expect(StringBase.short.extract('')).to be_nil
    end
  end

  describe 'Integer#string_id' do
    it 'encodes integer to string ID' do
      encoded = 123.string_id
      expect(encoded).to be_a(String)
      expect(encoded.string_id).to eq(123)
    end
  end

  describe 'String#string_id' do
    it 'decodes string ID from slug' do
      id = 456
      slug = "my-item-#{id.string_id}"
      expect(slug.string_id).to eq(id)
    end

    it 'raises for invalid string ID' do
      expect { 'invalid!!!'.string_id }.to raise_error(ArgumentError, /Bad ID/)
    end
  end
end
