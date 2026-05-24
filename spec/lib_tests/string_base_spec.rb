require 'test_helper'

describe Lux::Utils::StringBase do
  describe '.encode / .decode (short keys)' do
    it 'encodes and decodes integers' do
      encoded = Lux::Utils::StringBase.encode(12345)
      _(encoded).must_be_kind_of String
      _(Lux::Utils::StringBase.decode(encoded)).must_equal 12345
    end

    it 'encodes and decodes zero' do
      _(Lux::Utils::StringBase.encode(0)).must_equal ''
      # decode of empty string should return 0
      _(Lux::Utils::StringBase.decode('')).must_equal 0
    end

    it 'handles large integers' do
      large = 999_999_999
      encoded = Lux::Utils::StringBase.encode(large)
      _(Lux::Utils::StringBase.decode(encoded)).must_equal large
    end
  end

  describe '.short' do
    def encoder
      @encoder ||= Lux::Utils::StringBase.short
    end

    it 'uses SHORT_KEYS and multiplier 99' do
      encoded = encoder.encode(100)
      _(encoder.decode(encoded)).must_equal 100
    end

    it 'rejects invalid base on decode' do
      # 'c' decodes to index 1, which is not divisible by multiplier 99
      err = _{ encoder.decode('c') }.must_raise RuntimeError
      _(err.message).must_match(/Invalid decode base/)
    end
  end

  describe '.medium' do
    def encoder
      @encoder ||= Lux::Utils::StringBase.medium
    end

    it 'encodes and decodes with medium keys' do
      encoded = encoder.encode(42)
      _(encoder.decode(encoded)).must_equal 42
    end
  end

  describe '.long' do
    def encoder
      @encoder ||= Lux::Utils::StringBase.long
    end

    it 'encodes and decodes with long keys (case-sensitive)' do
      encoded = encoder.encode(1000)
      _(encoder.decode(encoded)).must_equal 1000
    end

    it 'produces shorter strings than medium for same value' do
      value = 100_000
      long_str = Lux::Utils::StringBase.long.encode(value)
      medium_str = Lux::Utils::StringBase.medium.encode(value)
      assert long_str.length <= medium_str.length
    end
  end

  describe '.uid' do
    it 'returns a 16-char string' do
      uid = Lux::Utils::StringBase.uid
      _(uid).must_be_kind_of String
      _(uid.length).must_equal 16
    end

    it 'generates unique values' do
      uids = 10.times.map { Lux::Utils::StringBase.uid; sleep(0.001); Lux::Utils::StringBase.uid }
      assert uids.uniq.length > 1
    end
  end

  describe '#rand' do
    it 'returns a random string of given length from key chars' do
      result = Lux::Utils::StringBase.medium.rand(10)
      _(result.length).must_equal 10
      result.chars.each { |c| _(c).must_match(/[a-z0-9]/) }
    end
  end

  describe '#extract' do
    it 'extracts ID from a URL-style slug' do
      id = 42
      slug = "some-title-#{Lux::Utils::StringBase.encode(id)}"
      extracted = Lux::Utils::StringBase.short.extract(slug)
      _(extracted).must_equal id
    end

    it 'returns nil for invalid slugs' do
      _(Lux::Utils::StringBase.short.extract('')).must_be_nil
    end
  end

  describe 'Integer#string_id' do
    it 'encodes integer to string ID' do
      encoded = 123.string_id
      _(encoded).must_be_kind_of String
      _(encoded.string_id).must_equal 123
    end
  end

  describe 'String#string_id' do
    it 'decodes string ID from slug' do
      id = 456
      slug = "my-item-#{id.string_id}"
      _(slug.string_id).must_equal id
    end

    it 'raises for invalid string ID' do
      err = _{ 'invalid!!!'.string_id }.must_raise ArgumentError
      _(err.message).must_match(/Bad ID/)
    end
  end
end
