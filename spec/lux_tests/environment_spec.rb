require 'test_helper'

describe Lux::Environment do
  describe 'initialization' do
    it 'raises for unsupported env name' do
      err = _{ Lux::Environment.new('staging') }.must_raise ArgumentError
      _(err.message).must_match(/Unsupported/)
    end

    it 'raises for empty env name' do
      err = _{ Lux::Environment.new('') }.must_raise ArgumentError
      _(err.message).must_match(/Unsupported/)
    end

    it 'accepts valid environment names' do
      %w(development production test).each do |name|
        Lux::Environment.new(name)
      end
    end
  end

  describe '.resolve_name' do
    def with_env vars
      saved = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it 'prefers LUX_ENV over RACK_ENV' do
      with_env('LUX_ENV' => 'production', 'RACK_ENV' => 'test') do
        _(Lux::Environment.resolve_name).must_equal 'production'
      end
    end

    it 'falls back to RACK_ENV when LUX_ENV is empty' do
      with_env('LUX_ENV' => '', 'RACK_ENV' => 'test') do
        _(Lux::Environment.resolve_name).must_equal 'test'
      end
    end

    it "defaults to 'development' when neither is set" do
      with_env('LUX_ENV' => nil, 'RACK_ENV' => nil) do
        _(Lux::Environment.resolve_name).must_equal 'development'
      end
    end
  end

  describe 'development environment' do
    def env
      @env ||= Lux::Environment.new('development')
    end

    it 'is development' do
      _(env.development?).must_equal true
    end

    it 'is dev' do
      _(env.dev?).must_equal true
    end

    it 'is not production' do
      _(env.production?).must_equal false
    end

    it 'is not prod' do
      _(env.prod?).must_equal false
    end
  end

  describe 'production environment' do
    def env
      @env ||= Lux::Environment.new('production')
    end

    it 'is not development' do
      _(env.development?).must_equal false
    end

    it 'is production' do
      _(env.production?).must_equal true
    end

    it 'is prod' do
      _(env.prod?).must_equal true
    end
  end

  describe 'test environment' do
    def env
      @env ||= Lux::Environment.new('test')
    end

    it 'is test' do
      _(env.test?).must_equal true
    end

    # test env is NOT production, so development? returns true
    it 'is development (non-production)' do
      _(env.development?).must_equal true
    end

    it 'is not production' do
      _(env.production?).must_equal false
    end
  end

  describe '#to_s' do
    it 'returns the actual env name' do
      _(Lux::Environment.new('production').to_s).must_equal 'production'
      _(Lux::Environment.new('development').to_s).must_equal 'development'
      _(Lux::Environment.new('test').to_s).must_equal 'test'
    end
  end

  describe '#==' do
    def env
      @env ||= Lux::Environment.new('test')
    end

    it 'compares by string name' do
      _(env == 'test').must_equal true
      _(env == 'production').must_equal false
    end

    it 'compares by symbol' do
      _(env == :test).must_equal true
    end

    it 'delegates to predicate methods' do
      _(env == :dev).must_equal true  # test is not production, so dev? is true
      _(env == :prod).must_equal false
    end

    it 'returns false for unknown keys instead of raising' do
      _(env == :totally_unknown_env).must_equal false
    end
  end
end
