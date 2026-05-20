require 'spec_helper'

describe Lux::Runtime do
  describe '#web? / #cli?' do
    it 'cli? is the inverse of web?' do
      rt = Lux::Runtime.new
      expect(rt.cli?).to eq(!rt.web?)
    end

    it 'honors LUX_WEB=true override' do
      previous = ENV['LUX_WEB']
      ENV['LUX_WEB'] = 'true'
      begin
        expect(Lux::Runtime.new.web?).to be true
      ensure
        previous.nil? ? ENV.delete('LUX_WEB') : ENV['LUX_WEB'] = previous
      end
    end

    it 'honors LUX_WEB=false override' do
      previous = ENV['LUX_WEB']
      ENV['LUX_WEB'] = 'false'
      begin
        expect(Lux::Runtime.new.web?).to be false
      ensure
        previous.nil? ? ENV.delete('LUX_WEB') : ENV['LUX_WEB'] = previous
      end
    end
  end

  describe '#rake?' do
    it 'returns false when not running under rake' do
      # this spec suite runs under rspec, not rake
      expect(Lux::Runtime.new.rake?).to be false
    end
  end
end
