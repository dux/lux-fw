require 'test_helper'

describe 'struct from hash/array' do
  it 'can create struct from hash' do
    opt = { foo: 1, bar: 2 }.to_lux_hash :foo, :bar, :baz
    _(opt.foo).must_equal 1
    _(opt.bar).must_equal 2
    _(opt.baz).must_be_nil
    _{ opt.abc }.must_raise NoMethodError
  end

  it 'expect to rasie argument error' do
    _{ { foo: 1, bar: 2 }.to_lux_hash [:foo, :baz] }.must_raise ArgumentError
  end

  it 'returns valid hash called 2x' do
    data = { foo: 1, bar: 2, baz: 3 }
    h1 = data.to_lux_hash
    h2 = h1.to_lux_hash :foo, :bar, :baz
    _{ h2.to_lux_hash :foo, :bar }.must_raise NoMethodError
  end
end
