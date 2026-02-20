require 'spec_helper'

describe Lux::Environment do
  describe 'initialization' do
    it 'raises for empty env name' do
      expect { Lux::Environment.new('') }.to raise_error(ArgumentError, /RACK_ENV is not defined/)
    end

    it 'raises for unsupported env name' do
      expect { Lux::Environment.new('staging') }.to raise_error(ArgumentError, /Unsupported/)
    end

    it 'accepts valid environment names' do
      %w(development production test).each do |name|
        expect { Lux::Environment.new(name) }.not_to raise_error
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
    it 'returns "production" for production' do
      expect(Lux::Environment.new('production').to_s).to eq('production')
    end

    it 'returns "development" for non-production' do
      expect(Lux::Environment.new('development').to_s).to eq('development')
      expect(Lux::Environment.new('test').to_s).to eq('development')
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
  end

  describe '#cli?' do
    it 'returns inverse of web?' do
      env = Lux::Environment.new('test')
      expect(env.cli?).to eq(!env.web?)
    end
  end

  describe 'LUX_ENV flags' do
    it 'detects show_errors from LUX_ENV' do
      env = Lux::Environment.new('test')
      # LUX_ENV is set to 'e' in spec_helper
      expect(env.show_errors?).to be true
    end
  end
end
