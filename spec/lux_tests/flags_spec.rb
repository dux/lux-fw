require 'test_helper'

describe Lux::Environment::Flags do
  def with_env vars
    saved = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe 'env defaults' do
    it 'is all-on in development' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Flags.new('development')
        _(m.debug?).must_equal  true
        _(m.reload?).must_equal true
      end
    end

    it 'is all-off in production' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Flags.new('production')
        _(m.debug?).must_equal  false
        _(m.reload?).must_equal false
      end
    end

    it 'is all-off in test' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Flags.new('test')
        _(m.debug?).must_equal  false
        _(m.reload?).must_equal false
      end
    end
  end

  describe 'ENV overrides' do
    it 'accepts true/false case-insensitively' do
      with_env('LUX_DEBUG' => 'TRUE', 'LUX_RELOAD' => 'False') do
        m = Lux::Environment::Flags.new('production')
        _(m.debug?).must_equal  true
        _(m.reload?).must_equal false
      end
    end

    it 'treats empty string as unset (uses default)' do
      with_env('LUX_DEBUG' => '', 'LUX_RELOAD' => '') do
        m = Lux::Environment::Flags.new('production')
        _(m.debug?).must_equal  false
        _(m.reload?).must_equal false
      end
    end

    it 'raises ArgumentError for invalid values' do
      with_env('LUX_DEBUG' => 'yes', 'LUX_RELOAD' => nil) do
        err = _{ Lux::Environment::Flags.new('development') }.must_raise ArgumentError
        _(err.message).must_match(/LUX_DEBUG="yes" is invalid/)
      end
    end

    it 'validates eagerly at boot for all flags' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => '1') do
        err = _{ Lux::Environment::Flags.new('development') }.must_raise ArgumentError
        _(err.message).must_match(/LUX_RELOAD/)
      end
    end
  end

  describe 'runtime setter' do
    it 'overrides ENV and default' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Flags.new('production')
        m.debug  = true
        m.reload = true

        _(m.debug?).must_equal  true
        _(m.reload?).must_equal true
      end
    end

    it 'overrides ENV' do
      with_env('LUX_DEBUG' => 'true') do
        m = Lux::Environment::Flags.new('production')
        m.debug = false
        _(m.debug?).must_equal false
      end
    end
  end

  describe 'debug? block form' do
    it 'returns yielded value when on' do
      with_env('LUX_DEBUG' => nil) do
        m = Lux::Environment::Flags.new('development')
        _(m.debug?('short') { 'long' }).must_equal 'long'
      end
    end

    it 'returns short when off' do
      with_env('LUX_DEBUG' => nil) do
        m = Lux::Environment::Flags.new('production')
        _(m.debug?('short') { 'long' }).must_equal 'short'
      end
    end

    it 'still works as plain boolean' do
      with_env('LUX_DEBUG' => nil) do
        m = Lux::Environment::Flags.new('development')
        _(m.debug?).must_equal true
      end
    end
  end

  # .env is loaded during Lux.boot!, by which point anything that logged early
  # has already built the flags off the pre-dotenv ENV.
  describe 'reload_env!' do
    it 'picks up an env var set after construction' do
      m = with_env('LUX_DEBUG' => nil) { Lux::Environment::Flags.new('production') }
      _(m.debug?).must_equal false

      with_env('LUX_DEBUG' => 'true') do
        m.reload_env!
        _(m.debug?).must_equal true
      end
    end

    it 'keeps a runtime override on top of the re-read env' do
      m = with_env('LUX_DEBUG' => nil) { Lux::Environment::Flags.new('production') }
      m.debug = false

      with_env('LUX_DEBUG' => 'true') do
        m.reload_env!
        _(m.debug?).must_equal false
      end
    end

    it 'leaves silent alone' do
      m = with_env('LUX_DEBUG' => nil) { Lux::Environment::Flags.new('production') }
      m.silent true

      with_env('LUX_DEBUG' => 'true') do
        m.reload_env!
        _(m.silent).must_equal true
      end
    end
  end

  describe 'silent' do
    it 'defaults to false and sets persistently' do
      m = Lux::Environment::Flags.new('production')
      _(m.silent).must_equal false
      m.silent true
      _(m.silent).must_equal true
      m.silent false
      _(m.silent).must_equal false
    end

    it 'mutes for a block and restores' do
      m = Lux::Environment::Flags.new('production')
      inside = nil
      m.silent { inside = m.silent }
      _(inside).must_equal true
      _(m.silent).must_equal false
    end

    it 'un-mutes for a block and restores' do
      m = Lux::Environment::Flags.new('production')
      m.silent true
      inside = nil
      m.silent(false) { inside = m.silent }
      _(inside).must_equal false
      _(m.silent).must_equal true
    end

    it 'restores even when the block raises' do
      m = Lux::Environment::Flags.new('production')
      _{ m.silent { raise 'boom' } }.must_raise RuntimeError
      _(m.silent).must_equal false
    end
  end

  # Call sites use the flat form; Lux.flags is the object behind it.
  describe 'Lux delegators' do
    it 'delegates predicates, block form and setters to Lux.flags' do
      prev = Lux.debug?

      Lux.debug = true
      _(Lux.debug?).must_equal true
      _(Lux.flags.debug?).must_equal true
      _(Lux.debug?('short') { 'long' }).must_equal 'long'

      Lux.debug = false
      _(Lux.debug?('short') { 'long' }).must_equal 'short'
    ensure
      Lux.debug = prev
    end

    it 'delegates silent, including the block form' do
      inside = nil
      Lux.silent(false) { inside = Lux.silent }
      _(inside).must_equal false
      # test_helper mutes the suite; the block must have restored that
      _(Lux.silent).must_equal true
    end
  end
end
