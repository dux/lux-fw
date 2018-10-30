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

    expect{ data.naat }.to raise_error(NoMethodError)
    expect{ data[:naat] }.to raise_error(NoMethodError)
  end

  it 'should create from hash' do
    data = { name: 'Foo', num1: 1 }.to_opts! :name, :num1, :num2

    expect(data.name).to eq 'Foo'
    expect(data.num1).to eq 1
  end
end
