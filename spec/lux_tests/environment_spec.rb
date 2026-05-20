require 'spec_helper'

describe Lux::Environment do
  describe 'initialization' do
    it 'raises for unsupported env name' do
      expect { Lux::Environment.new('staging') }.to raise_error(ArgumentError, /Unsupported/)
    end

    it 'raises for empty env name' do
      expect { Lux::Environment.new('') }.to raise_error(ArgumentError, /Unsupported/)
    end

    it 'accepts valid environment names' do
      %w(development production test).each do |name|
        expect { Lux::Environment.new(name) }.not_to raise_error
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
        expect(Lux::Environment.resolve_name).to eq('production')
      end
    end

    it 'falls back to RACK_ENV when LUX_ENV is empty' do
      with_env('LUX_ENV' => '', 'RACK_ENV' => 'test') do
        expect(Lux::Environment.resolve_name).to eq('test')
      end
    end

    it "defaults to 'development' when neither is set" do
      with_env('LUX_ENV' => nil, 'RACK_ENV' => nil) do
        expect(Lux::Environment.resolve_name).to eq('development')
      end
    end
  end

  describe 'development environment' do
    let(:env) { Lux::Environment.new('development') }

    it { expect(env.development?).to be true }
    it { expect(env.dev?).to be true }
    it { expect(env.production?).to be false }
    it { expect(env.prod?).to be false }
  end

  describe 'production environment' do
    let(:env) { Lux::Environment.new('production') }

    it { expect(env.development?).to be false }
    it { expect(env.production?).to be true }
    it { expect(env.prod?).to be true }
  end

  describe 'test environment' do
    let(:env) { Lux::Environment.new('test') }

    it { expect(env.test?).to be true }
    # test env is NOT production, so development? returns true
    it { expect(env.development?).to be true }
    it { expect(env.production?).to be false }
  end

  describe '#to_s' do
    it 'returns the actual env name' do
      expect(Lux::Environment.new('production').to_s).to eq('production')
      expect(Lux::Environment.new('development').to_s).to eq('development')
      expect(Lux::Environment.new('test').to_s).to eq('test')
    end
  end

  describe '#==' do
    let(:env) { Lux::Environment.new('test') }

    it 'compares by string name' do
      expect(env == 'test').to be true
      expect(env == 'production').to be false
    end

    it 'compares by symbol' do
      expect(env == :test).to be true
    end

    it 'delegates to predicate methods' do
      expect(env == :dev).to be true  # test is not production, so dev? is true
      expect(env == :prod).to be false
    end

    it 'returns false for unknown keys instead of raising' do
      expect { env == :totally_unknown_env }.not_to raise_error
      expect(env == :totally_unknown_env).to be false
    end
  end
end
