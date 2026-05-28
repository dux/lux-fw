require 'test_helper'

describe Lux::Environment::Mode do
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
        m = Lux::Environment::Mode.new('development')
        _(m.debug?).must_equal  true
        _(m.reload?).must_equal true
      end
    end

    it 'is all-off in production' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Mode.new('production')
        _(m.debug?).must_equal  false
        _(m.reload?).must_equal false
      end
    end

    it 'is all-off in test' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Mode.new('test')
        _(m.debug?).must_equal  false
        _(m.reload?).must_equal false
      end
    end
  end

  describe 'ENV overrides' do
    it 'accepts true/false case-insensitively' do
      with_env('LUX_DEBUG' => 'TRUE', 'LUX_RELOAD' => 'False') do
        m = Lux::Environment::Mode.new('production')
        _(m.debug?).must_equal  true
        _(m.reload?).must_equal false
      end
    end

    it 'treats empty string as unset (uses default)' do
      with_env('LUX_DEBUG' => '', 'LUX_RELOAD' => '') do
        m = Lux::Environment::Mode.new('production')
        _(m.debug?).must_equal  false
        _(m.reload?).must_equal false
      end
    end

    it 'raises ArgumentError for invalid values' do
      with_env('LUX_DEBUG' => 'yes', 'LUX_RELOAD' => nil) do
        err = _{ Lux::Environment::Mode.new('development') }.must_raise ArgumentError
        _(err.message).must_match(/LUX_DEBUG="yes" is invalid/)
      end
    end

    it 'validates eagerly at boot for all flags' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => '1') do
        err = _{ Lux::Environment::Mode.new('development') }.must_raise ArgumentError
        _(err.message).must_match(/LUX_RELOAD/)
      end
    end
  end

  describe 'runtime setter' do
    it 'overrides ENV and default' do
      with_env('LUX_DEBUG' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Environment::Mode.new('production')
        m.debug  = true
        m.reload = true

        _(m.debug?).must_equal  true
        _(m.reload?).must_equal true
      end
    end

    it 'overrides ENV' do
      with_env('LUX_DEBUG' => 'true') do
        m = Lux::Environment::Mode.new('production')
        m.debug = false
        _(m.debug?).must_equal false
      end
    end
  end

  describe 'debug? block form' do
    it 'returns yielded value when on' do
      with_env('LUX_DEBUG' => nil) do
        m = Lux::Environment::Mode.new('development')
        _(m.debug?('short') { 'long' }).must_equal 'long'
      end
    end

    it 'returns short when off' do
      with_env('LUX_DEBUG' => nil) do
        m = Lux::Environment::Mode.new('production')
        _(m.debug?('short') { 'long' }).must_equal 'short'
      end
    end

    it 'still works as plain boolean' do
      with_env('LUX_DEBUG' => nil) do
        m = Lux::Environment::Mode.new('development')
        _(m.debug?).must_equal true
      end
    end
  end
end
