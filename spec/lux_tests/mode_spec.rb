require 'spec_helper'

describe Lux::Mode do
  def with_env vars
    saved = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe 'env defaults' do
    it 'is all-on in development' do
      with_env('LUX_LOG' => nil, 'LUX_ERRORS' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Mode.new('development')
        expect(m.log?).to    be true
        expect(m.errors?).to be true
        expect(m.reload?).to be true
      end
    end

    it 'is all-off in production' do
      with_env('LUX_LOG' => nil, 'LUX_ERRORS' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Mode.new('production')
        expect(m.log?).to    be false
        expect(m.errors?).to be false
        expect(m.reload?).to be false
      end
    end

    it 'is all-off in test' do
      with_env('LUX_LOG' => nil, 'LUX_ERRORS' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Mode.new('test')
        expect(m.log?).to    be false
        expect(m.errors?).to be false
        expect(m.reload?).to be false
      end
    end
  end

  describe 'ENV overrides' do
    it 'accepts true/false case-insensitively' do
      with_env('LUX_LOG' => 'TRUE', 'LUX_ERRORS' => 'False', 'LUX_RELOAD' => 'true') do
        m = Lux::Mode.new('production')
        expect(m.log?).to    be true
        expect(m.errors?).to be false
        expect(m.reload?).to be true
      end
    end

    it 'treats empty string as unset (uses default)' do
      with_env('LUX_LOG' => '', 'LUX_ERRORS' => '', 'LUX_RELOAD' => '') do
        m = Lux::Mode.new('production')
        expect(m.log?).to    be false
        expect(m.errors?).to be false
        expect(m.reload?).to be false
      end
    end

    it 'raises ArgumentError for invalid values' do
      with_env('LUX_LOG' => 'yes', 'LUX_ERRORS' => nil, 'LUX_RELOAD' => nil) do
        expect { Lux::Mode.new('development') }.to raise_error(ArgumentError, /LUX_LOG="yes" is invalid/)
      end
    end

    it 'validates eagerly at boot for all flags' do
      with_env('LUX_LOG' => nil, 'LUX_ERRORS' => '1', 'LUX_RELOAD' => nil) do
        expect { Lux::Mode.new('development') }.to raise_error(ArgumentError, /LUX_ERRORS/)
      end
    end
  end

  describe 'runtime setter' do
    it 'overrides ENV and default' do
      with_env('LUX_LOG' => nil, 'LUX_ERRORS' => nil, 'LUX_RELOAD' => nil) do
        m = Lux::Mode.new('production')
        m.log    = true
        m.errors = true
        m.reload = true

        expect(m.log?).to    be true
        expect(m.errors?).to be true
        expect(m.reload?).to be true
      end
    end

    it 'overrides ENV' do
      with_env('LUX_LOG' => 'true') do
        m = Lux::Mode.new('production')
        m.log = false
        expect(m.log?).to be false
      end
    end
  end

  describe 'errors? block form' do
    it 'returns yielded value when on' do
      with_env('LUX_ERRORS' => nil) do
        m = Lux::Mode.new('development')
        expect(m.errors?('short') { 'long' }).to eq('long')
      end
    end

    it 'returns short when off' do
      with_env('LUX_ERRORS' => nil) do
        m = Lux::Mode.new('production')
        expect(m.errors?('short') { 'long' }).to eq('short')
      end
    end

    it 'still works as plain boolean' do
      with_env('LUX_ERRORS' => nil) do
        m = Lux::Mode.new('development')
        expect(m.errors?).to be true
      end
    end
  end
end
