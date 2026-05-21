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

  describe '.defer' do
    it 'returns a Thread' do
      thread = Lux.defer { true }
      expect(thread).to be_a(Thread)
      thread.join(1)
    end

    it 'raises ArgumentError without a block' do
      expect { Lux.defer }.to raise_error(ArgumentError, /Block not given/)
    end

    it 'defaults context to Lux.current.dup' do
      parent = Lux::Current.new('http://test')
      parent[:marker] = 'from-parent'

      received = nil
      Lux.defer { |ctx| received = ctx }.join(1)

      expect(received).to be_a(Lux::Current)
      expect(received).not_to equal(parent)
      expect(received[:marker]).to eq('from-parent')
    end

    it 'passes a custom context through untouched' do
      custom = { user_id: 42 }
      received = nil
      Lux.defer(context: custom) { |ctx| received = ctx }.join(1)

      expect(received).to equal(custom)
    end

    it 'starts with a clean Lux.current inside the thread' do
      parent = Lux::Current.new('http://test')

      inside = nil
      Lux.defer { inside = Lux.current }.join(1)

      expect(inside).to be_a(Lux::Current)
      expect(inside).not_to equal(parent)
    end

    it 'does not mutate the parent Lux.current binding' do
      parent = Lux::Current.new('http://test')

      Lux.defer do
        # touching Lux.current in the bg thread should not leak across
        Lux.current[:bg_only] = true
      end.join(1)

      expect(Thread.current[:lux]).to equal(parent)
      expect(parent[:bg_only]).to be_nil
    end

    it 'supports zero-arity blocks' do
      called = false
      Lux.defer { called = true }.join(1)
      expect(called).to be true
    end

    it 'passes context to one-arity blocks' do
      custom = Object.new
      received = nil
      Lux.defer(context: custom) { |ctx| received = ctx }.join(1)
      expect(received).to equal(custom)
    end

    it 'respects an explicit timeout' do
      logged = nil
      allow(Lux.logger).to receive(:error) { |msg| logged = msg }

      Lux.defer(timeout: 0.05) { sleep 0.5 }.join(1)

      expect(logged.to_s).to match(/execution expired|Lux\.defer error/)
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
