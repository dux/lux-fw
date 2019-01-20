require 'spec_helper'

describe Hash do
  it 'should create a tag by hash' do
    tag = { a:'123', b:'456' }.tag(:div, 'abc')
    expect(tag).to eq(%[<div a="123" b="456">abc</div>])
  end

  it 'should create a hash with indifferent access' do
    test = HashWithIndifferentAccess.new({
      a: 1,
      'b' => { 'c': { d:2 } }
    })

    expect(test[:a]).to eq(1)
    expect(test['a']).to eq(1)

    expect(test.key?(:a)).to eq(true)
    expect(test.key?('a')).to eq(true)
    expect(test.key?(:c)).to eq(false)
    expect(test.key?('c')).to eq(false)

    expect(test['b']['c']['d']).to eq(2)
    expect(test[:b][:c][:d]).to eq(2)

    expect(test.dig('b', 'c', :d)).to eq(2)
    expect(test.dig(:b, :c, 'd')).to eq(2)

    test.delete 'a'
    expect(test[:a]).to eq(nil)
  end
end
