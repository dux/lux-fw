require 'test_helper'

describe 'tesing params' do
  def set(*args)
    Lux.type(*args)
  end

  describe 'global checks and' do
    it 'raises error on not existing required attribute' do
      _{ set :wtf, true }.must_raise ArgumentError
    end
  end

  describe 'validates' do
    it 'boolean' do
      _(set :boolean, true).must_equal true
      _(set :boolean, 'true').must_equal true
      _(set :boolean, 'false').must_equal false
      _(set :boolean, 1).must_equal true
      _(set :boolean, 'on').must_equal true
      _(set :boolean, nil, default: false).must_equal false
      _{ set :boolean, 'aaa' }.must_raise TypeError
    end

    it 'integer' do
      _(set :integer, 123).must_equal 123
      _(set :integer, '123').must_equal 123
      _(set :integer, 0).must_equal 0
      _(set :integer, '0').must_equal 0
      _(set :integer, nil, req: true).must_be_nil
      _(set :integer, nil).must_be_nil
      _(set :integer, nil, default: 1).must_equal 1

      _{ set :integer, 100, max: 99  }.must_raise TypeError
      _{ set :integer, 99,  min: 100 }.must_raise TypeError
    end

    it 'string' do
      _(set :string, 123).must_equal '123'
      _(set :string, ' 123 ').must_equal '123'
      _(set :string, nil, default: '').must_equal ''
    end

    it 'float' do
      _(set :float, '1.2345').must_equal 1.2345
      _(set :float, 1.2345).must_equal 1.2345
      _(set :float, 1.2345, round: 2).must_equal 1.23
      _(set :float, nil, round: 2).must_be_nil

      _{ set :float, 100, max: 99  }.must_raise TypeError
      _{ set :float, 99,  min: 100 }.must_raise TypeError
    end

    it 'date' do
      _(set :date, '1.2.2345.').must_equal DateTime.parse('1.2.2345.')
      _(set :date, '1.2.2345. 13:34').must_equal DateTime.parse('1.2.2345.')
      _{ set :date, '1.2.2345.', min: '1.2.3345.' }.must_raise TypeError
      _{ set :date, '1.2.2345.', max: '1.2.1345.' }.must_raise TypeError
    end

    it 'datetime' do
      _(set :datetime, '1.2.2345.').must_equal DateTime.parse('1.2.2345.')
      _(set :datetime, '1.2.2345. 13:34').must_equal DateTime.parse('1.2.2345 13:34')
      _{ set :date, '1.2.2345.', min: '1.2.3345.' }.must_raise TypeError
      _{ set :date, '1.2.2345.', max: '1.2.1345.' }.must_raise TypeError
    end

    it 'hash' do
      _(set :hash, { foo: 'bar' }).must_equal({ foo: 'bar' })
      _(set :hash, { foo: 'bar', bar: 'baz' }, allow: [:foo]).must_equal({ foo: 'bar' })
    end
  end

  describe 'various checks as' do
    it 'checks values in params' do
      _(set :string, 'red', values: ['red', 'green', 'blue']).must_equal 'red'
      _{ set :string, 'red', values: ['green', 'blue'] }.must_raise TypeError
    end
  end
end
