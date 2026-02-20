require 'spec_helper'

describe Lux::Response::Flash do
  let(:flash) {
    f = Lux::Response::Flash.new
    f.info  = 'foo'
    f.error = "b'ar"
    f.error 'ba"z'
    f
  }

  describe '#clear' do
    it 'returns and clears flash messages' do
      msg = flash.clear
      expect(msg[:info]).to eq ['foo']
      expect(msg[:error]).to eq ["b'ar", 'ba"z']
    end

    it 'empties the flash after clearing' do
      flash.clear
      expect(flash.to_h).to eq({})
    end
  end

  describe '#clear_for_js' do
    it 'joins messages with comma for JS consumption' do
      expect(flash.clear_for_js[:error]).to eq %{b'ar, ba"z}
      expect(flash.clear_for_js[:info]).to be_nil # already cleared
    end
  end

  describe 'message types' do
    it 'supports info messages' do
      f = Lux::Response::Flash.new
      f.info 'hello'
      expect(f.to_h[:info]).to eq(['hello'])
    end

    it 'supports error messages' do
      f = Lux::Response::Flash.new
      f.error 'bad thing'
      expect(f.to_h[:error]).to eq(['bad thing'])
    end

    it 'supports warning messages' do
      f = Lux::Response::Flash.new
      f.warning 'careful'
      expect(f.to_h[:warning]).to eq(['careful'])
    end

    it 'supports assignment syntax' do
      f = Lux::Response::Flash.new
      f.info = 'assigned'
      expect(f.to_h[:info]).to eq(['assigned'])
    end
  end

  describe '#present? / #empty?' do
    it 'returns truthy when messages exist' do
      expect(flash.present?).to be_truthy
      expect(flash.empty?).to be false
    end

    it 'returns falsey when empty' do
      f = Lux::Response::Flash.new
      expect(f.present?).to be_falsey
      expect(f.empty?).to be true
    end
  end

  describe 'deduplication' do
    it 'does not add duplicate consecutive messages' do
      f = Lux::Response::Flash.new
      f.error 'same'
      f.error 'same'
      expect(f.to_h[:error]).to eq(['same'])
    end
  end

  describe 'max limit' do
    it 'limits messages to 5 per type' do
      f = Lux::Response::Flash.new
      10.times { |i| f.error "error #{i}" }
      expect(f.to_h[:error].length).to eq(5)
    end
  end

  describe 'blank messages' do
    it 'ignores blank messages' do
      f = Lux::Response::Flash.new
      f.info ''
      f.info nil
      expect(f.to_h.keys).to be_empty
    end
  end

  describe 'initialization with existing data' do
    it 'restores from a hash' do
      f = Lux::Response::Flash.new({ info: ['restored'] })
      expect(f.to_h[:info]).to eq(['restored'])
    end
  end
end