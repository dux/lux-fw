require 'test_helper'

describe Lux::Runtime do
  describe '#web? / #cli?' do
    it 'cli? is the inverse of web?' do
      rt = Lux::Runtime.new
      _(rt.cli?).must_equal(!rt.web?)
    end

    it 'honors LUX_WEB=true override' do
      previous = ENV['LUX_WEB']
      ENV['LUX_WEB'] = 'true'
      begin
        _(Lux::Runtime.new.web?).must_equal true
      ensure
        previous.nil? ? ENV.delete('LUX_WEB') : ENV['LUX_WEB'] = previous
      end
    end

    it 'honors LUX_WEB=false override' do
      previous = ENV['LUX_WEB']
      ENV['LUX_WEB'] = 'false'
      begin
        _(Lux::Runtime.new.web?).must_equal false
      ensure
        previous.nil? ? ENV.delete('LUX_WEB') : ENV['LUX_WEB'] = previous
      end
    end
  end

  describe '#rake?' do
    it 'returns false when not running under rake' do
      # this spec suite runs under minitest, not rake
      _(Lux::Runtime.new.rake?).must_equal false
    end
  end
end
