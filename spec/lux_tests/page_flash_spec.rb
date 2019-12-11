require 'spec_helper'

describe Lux::Response::Flash do
  let(:f) {
    flash       = Lux::Response::Flash.new
    flash.info  = 'foo'
    flash.error = "b'ar"
    flash.error 'ba"z'
    flash
  }

  it 'Set and get flash message' do
    msg = f.clear
    expect(msg[:info]).to eq ['foo']
    expect(msg[:error]).to eq ["b'ar", 'ba"z']
  end

  it 'Format js response' do
    expect(f.clear_for_js[:error]).to eq %{b'ar, ba"z}
  end

end