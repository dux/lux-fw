require 'spec_helper'

describe Hash do
  it 'should create a tag by hash' do
    tag = { a:'123', b:'456' }.tag(:div, 'abc')
    expect(tag).to eq(%[<div a="123" b="456">abc</div>])
  end
end
