require 'spec_helper'

describe Lux do
  describe '.root' do
    it 'returns a Pathname' do
      expect(Lux.root).to be_a(Pathname)
    end

    it 'is frozen' do
      expect(Lux.root).to be_frozen
    end
  end

  describe '.fw_root' do
    it 'returns a Pathname' do
      expect(Lux.fw_root).to be_a(Pathname)
    end

    it 'is frozen' do
      expect(Lux.fw_root).to be_frozen
    end

    it 'points to the framework directory' do
      expect((Lux.fw_root + 'lib/lux-fw.rb')).to exist
    end
  end

  describe 'VERSION' do
    it 'is defined and non-empty' do
      expect(Lux::VERSION).to be_a(String)
      expect(Lux::VERSION).not_to be_empty
    end

    it 'follows semver format' do
      expect(Lux::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe '.speed' do
    it 'measures block execution time' do
      result = Lux.speed { sleep(0.001) }
      expect(result).to be_a(String)
      expect(result).to match(/\d+(\.\d+)?\s*(ms|sec)/)
    end

    it 'returns ms for fast operations' do
      result = Lux.speed { 1 + 1 }
      expect(result).to include('ms')
    end
  end

  describe '.delay' do
    it 'returns a Thread' do
      thread = Lux.delay { true }
      expect(thread).to be_a(Thread)
      thread.join(1)
    end
  end

  describe '.env' do
    it 'returns an Environment instance' do
      expect(Lux.env).to be_a(Lux::Environment)
    end

    it 'responds to test?' do
      expect(Lux.env.test?).to be true
    end
  end

  describe '.config' do
    it 'returns a config object' do
      expect(Lux.config).to respond_to(:[])
    end

    it 'has host configured' do
      expect(Lux.config.host).to eq('http://test')
    end

    it 'has secret configured' do
      expect(Lux.config.secret).to eq('test-secret')
    end
  end

  describe '.cache' do
    before { Lux::Current.new('http://test') }

    it 'returns a Cache instance' do
      expect(Lux.cache).to be_a(Lux::Cache)
    end
  end
end
