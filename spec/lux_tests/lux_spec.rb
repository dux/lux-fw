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

    # Pool-backed defer returns nil (not a Thread); tests use a Queue
    # barrier to wait for completion deterministically.
    def wait_defer(timeout: 1, &block)
      done = Queue.new
      ret  = Lux.defer { |ctx| block.call(ctx); done << true }
      done.pop
      ret
    end

    it 'returns nil (pool-backed, no thread handle)' do
      _(Lux.defer { true }).must_be_nil
    end

    it 'raises ArgumentError without a block' do
      err = _{ Lux.defer }.must_raise ArgumentError
      _(err.message).must_match(/Block not given/)
    end

    it 'defaults context to Lux.current.dup' do
      parent = Lux::Current.new('http://test')
      parent[:marker] = 'from-parent'

      received = nil
      wait_defer { |ctx| received = ctx }

      _(received).must_be_kind_of Lux::Current
      _(received.equal?(parent)).must_equal false
      _(received[:marker]).must_equal 'from-parent'
    end

    it 'passes a custom context through untouched' do
      custom = { user_id: 42 }
      received = nil
      done = Queue.new
      Lux.defer(context: custom) { |ctx| received = ctx; done << true }
      done.pop

      _(received.equal?(custom)).must_equal true
    end

    it 'starts with a clean Lux.current inside the thread' do
      parent = Lux::Current.new('http://test')

      inside = nil
      wait_defer { inside = Lux.current }

      _(inside).must_be_kind_of Lux::Current
      _(inside.equal?(parent)).must_equal false
    end

    it 'does not mutate the parent Lux.current binding' do
      parent = Lux::Current.new('http://test')

      wait_defer do
        # touching Lux.current in the bg thread should not leak across
        Lux.current[:bg_only] = true
      end

      _(Thread.current[:lux].equal?(parent)).must_equal true
      _(parent[:bg_only]).must_be_nil
    end

    it 'supports zero-arity blocks' do
      called = false
      done = Queue.new
      Lux.defer { called = true; done << true }
      done.pop
      _(called).must_equal true
    end

    it 'passes context to one-arity blocks' do
      custom = Object.new
      received = nil
      done = Queue.new
      Lux.defer(context: custom) { |ctx| received = ctx; done << true }
      done.pop
      _(received.equal?(custom)).must_equal true
    end

    it 'respects an explicit timeout' do
      buf  = StringIO.new
      prev = Lux::LOGGER_CACHE[:defer_worker]
      Lux::LOGGER_CACHE[:defer_worker] = Logger.new(buf)

      begin
        Lux.defer(timeout: 0.05) { sleep 0.5 }
        # No thread handle; poll the log buffer until the worker writes.
        deadline = Time.now + 2
        sleep 0.02 until buf.string =~ /timeout|expired/ || Time.now > deadline
      ensure
        if prev
          Lux::LOGGER_CACHE[:defer_worker] = prev
        else
          Lux::LOGGER_CACHE.delete(:defer_worker)
        end
      end

      _(buf.string).must_match(/timeout|execution expired/)
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

  describe '.logger' do
    it 'does not write the default logger to screen in test' do
      previous = Lux.instance_variable_get(:@default_logger)
      Lux.remove_instance_variable(:@default_logger)

      output = capture_stderr { Lux.logger.error 'hidden test error' }

      _(output).must_equal ''
    ensure
      Lux.instance_variable_set(:@default_logger, previous)
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
