require 'test_helper'

describe Lux do
  describe '.root' do
    it 'returns a Pathname' do
      _(Lux.root).must_be_kind_of Pathname
    end

    it 'is frozen' do
      _(Lux.root.frozen?).must_equal true
    end
  end

  describe '.fw_root' do
    it 'returns a Pathname' do
      _(Lux.fw_root).must_be_kind_of Pathname
    end

    it 'is frozen' do
      _(Lux.fw_root.frozen?).must_equal true
    end

    it 'points to the framework directory' do
      _((Lux.fw_root + 'lib/lux-fw.rb').exist?).must_equal true
    end
  end

  describe 'VERSION' do
    it 'is defined and non-empty' do
      _(Lux::VERSION).must_be_kind_of String
      _(Lux::VERSION.empty?).must_equal false
    end

    it 'follows semver format' do
      _(Lux::VERSION).must_match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe '.speed' do
    it 'measures block execution time' do
      result = Lux.speed { sleep(0.001) }
      _(result).must_be_kind_of String
      _(result).must_match(/\d+(\.\d+)?\s*(ms|sec)/)
    end

    it 'returns ms for fast operations' do
      result = Lux.speed { 1 + 1 }
      _(result).must_include 'ms'
    end
  end

  describe '.defer' do
    before { Lux.config[:delay_timeout] ||= 30 }

    it 'returns a Thread' do
      thread = Lux.defer { true }
      _(thread).must_be_kind_of Thread
      thread.join(1)
    end

    it 'raises ArgumentError without a block' do
      err = _{ Lux.defer }.must_raise ArgumentError
      _(err.message).must_match(/Block not given/)
    end

    it 'defaults context to Lux.current.dup' do
      parent = Lux::Current.new('http://test')
      parent[:marker] = 'from-parent'

      received = nil
      Lux.defer { |ctx| received = ctx }.join(1)

      _(received).must_be_kind_of Lux::Current
      _(received.equal?(parent)).must_equal false
      _(received[:marker]).must_equal 'from-parent'
    end

    it 'passes a custom context through untouched' do
      custom = { user_id: 42 }
      received = nil
      Lux.defer(context: custom) { |ctx| received = ctx }.join(1)

      _(received.equal?(custom)).must_equal true
    end

    it 'starts with a clean Lux.current inside the thread' do
      parent = Lux::Current.new('http://test')

      inside = nil
      Lux.defer { inside = Lux.current }.join(1)

      _(inside).must_be_kind_of Lux::Current
      _(inside.equal?(parent)).must_equal false
    end

    it 'does not mutate the parent Lux.current binding' do
      parent = Lux::Current.new('http://test')

      Lux.defer do
        # touching Lux.current in the bg thread should not leak across
        Lux.current[:bg_only] = true
      end.join(1)

      _(Thread.current[:lux].equal?(parent)).must_equal true
      _(parent[:bg_only]).must_be_nil
    end

    it 'supports zero-arity blocks' do
      called = false
      Lux.defer { called = true }.join(1)
      _(called).must_equal true
    end

    it 'passes context to one-arity blocks' do
      custom = Object.new
      received = nil
      Lux.defer(context: custom) { |ctx| received = ctx }.join(1)
      _(received.equal?(custom)).must_equal true
    end

    it 'respects an explicit timeout' do
      buf = StringIO.new
      prev = Lux.instance_variable_get(:@default_logger)
      Lux.instance_variable_set(:@default_logger, Logger.new(buf))

      begin
        Lux.defer(timeout: 0.05) { sleep 0.5 }.join(1)
      ensure
        Lux.instance_variable_set(:@default_logger, prev)
      end

      _(buf.string).must_match(/execution expired|Lux\.defer error/)
    end
  end

  describe '.env' do
    it 'returns an Environment instance' do
      _(Lux.env).must_be_kind_of Lux::Environment
    end

    it 'responds to test?' do
      _(Lux.env.test?).must_equal true
    end
  end

  describe '.config' do
    it 'returns a config object' do
      _(Lux.config.respond_to?(:[])).must_equal true
    end

    it 'has host configured' do
      _(Lux.config.host).must_equal 'http://test'
    end

    it 'has secret configured' do
      _(Lux.config.secret).must_equal 'test-secret'
    end
  end

  describe '.cache' do
    before { Lux::Current.new('http://test') }

    it 'returns a Cache instance' do
      _(Lux.cache).must_be_kind_of Lux::Cache
    end
  end
end
