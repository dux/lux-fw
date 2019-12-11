require 'spec_helper'

describe FreeStruct do
  let(:get_free_struct) {
    FreeStruct.new foo: 'bar', baz: 4
  }

  it 'should create a valid object' do
    data = get_free_struct

    expect(data.foo).to eq('bar')
    expect(data.baz).to eq(4)

    data.foo = 'baz'
    expect(data.foo).to eq('baz')
    expect(data[:foo]).to eq('baz')

    expect{ data.naat }.to raise_error(ArgumentError)
    expect{ data[:naat] }.to raise_error(ArgumentError)
  end

  it 'should create from hash' do
    data = { name: 'Foo', num1: 1 }.to_opts :name, :num1, :num2

    expect(data.name).to eq 'Foo'
    expect(data.num1).to eq 1
  end

  it 'should check types' do
    data = { name: 'Foo', num: 1 }.to_opts name: String, num: Integer, not_defined: Integer

    expect(data.name).to eq 'Foo'
    expect(data.num).to eq 1
  end

  it 'should raise on bad type' do
    data = { name: 'Foo', num: 1 }
    expect{ data.to_opts({name: String, num: String}) }.to raise_error(ArgumentError)
    expect{ data.to_opts(:name) }.to raise_error(ArgumentError)
  end
end
