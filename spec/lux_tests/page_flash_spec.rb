require 'test_helper'

describe Lux::Response::Flash do
  def flash
    @flash ||= begin
      f = Lux::Response::Flash.new
      f.info  = 'foo'
      f.error = "b'ar"
      f.error 'ba"z'
      f
    end
  end

  describe '#clear' do
    it 'returns and clears flash messages' do
      msg = flash.clear
      _(msg[:info]).must_equal ['foo']
      _(msg[:error]).must_equal ["b'ar", 'ba"z']
    end

    it 'empties the flash after clearing' do
      flash.clear
      _(flash.to_h).must_equal({})
    end
  end

  describe '#clear_for_js' do
    it 'joins messages with comma for JS consumption' do
      _(flash.clear_for_js[:error]).must_equal %{b'ar, ba"z}
      _(flash.clear_for_js[:info]).must_be_nil # already cleared
    end
  end

  describe 'message types' do
    it 'supports info messages' do
      f = Lux::Response::Flash.new
      f.info 'hello'
      _(f.to_h[:info]).must_equal ['hello']
    end

    it 'supports error messages' do
      f = Lux::Response::Flash.new
      f.error 'bad thing'
      _(f.to_h[:error]).must_equal ['bad thing']
    end

    it 'supports warning messages' do
      f = Lux::Response::Flash.new
      f.warning 'careful'
      _(f.to_h[:warning]).must_equal ['careful']
    end

    it 'supports assignment syntax' do
      f = Lux::Response::Flash.new
      f.info = 'assigned'
      _(f.to_h[:info]).must_equal ['assigned']
    end
  end

  describe '#present? / #empty?' do
    it 'returns truthy when messages exist' do
      assert flash.present?
      refute flash.empty?
    end

    it 'returns falsey when empty' do
      f = Lux::Response::Flash.new
      refute f.present?
      assert f.empty?
    end
  end

  describe 'deduplication' do
    it 'does not add duplicate consecutive messages' do
      f = Lux::Response::Flash.new
      f.error 'same'
      f.error 'same'
      _(f.to_h[:error]).must_equal ['same']
    end
  end

  describe 'max limit' do
    it 'limits messages to 5 per type' do
      f = Lux::Response::Flash.new
      10.times { |i| f.error "error #{i}" }
      _(f.to_h[:error].length).must_equal 5
    end
  end

  describe 'blank messages' do
    it 'ignores blank messages' do
      f = Lux::Response::Flash.new
      f.info ''
      f.info nil
      _(f.to_h.keys).must_be_empty
    end
  end

  describe 'initialization with existing data' do
    it 'restores from a hash' do
      f = Lux::Response::Flash.new({ info: ['restored'] })
      _(f.to_h[:info]).must_equal ['restored']
    end
  end
end
