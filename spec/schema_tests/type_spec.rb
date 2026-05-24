require 'test_helper'
require_relative './fixtures'

describe Lux::Schema do
  before do
    @test  = Test.new
    @rules = TestSchema
  end

  it 'should render string' do
    schema = Lux.schema do
      data downcase: true
    end

    data  = { data: '  aBc  ' }
    errors = schema.validate data
    _(data[:data]).must_equal 'abc'
  end

  it 'speed should be Float' do
    @test.speed = '10'
    errors = @rules.validate(@test)
    _(@test.speed.class).must_equal Float
    _(@test.speed).must_equal 10.0
  end

  it 'email to be valid' do
    @test.email = 'dux@dux.net'
    @rules.valid? @test
    _(@test.email).must_equal 'dux@dux.net'
    _(@test[:email]).must_equal 'dux@dux.net'
  end

  it 'email to fail' do
    @test.email = 'duxdux.net'
    errors = @rules.validate @test
    _(errors[:email].include?('@')).must_equal true
  end

  it 'shout get right boolean values' do
    schema = Lux.schema do
      foo  true
      bar  false
      baz  :boolean
    end

    data = {}
    errors = schema.validate data

    _(errors[:foo]).must_be_nil
    _(errors[:bar]).must_be_nil
    _(errors[:baz]).must_be_nil

    data = { foo: 'off', bar: '1', baz: 'false' }
    errors = schema.validate data
    _(data).must_equal(foo: false, bar: true, baz: false)
    _(errors.keys.length).must_equal 0
  end

  it 'url shuld fail then pass' do
    schema = Lux.schema do
      url  :url
    end

    errors = schema.validate url: 'slashdot.org'
    _(errors[:url]).must_include 'not starting'

    errors = schema.validate url: 'https://slashdot.org'
    _(errors[:url]).must_be_nil
  end

  it 'should convert empty strings to nil' do
    schema = Lux.schema do
      foo
    end
    h = { foo: '', bar: '' }
    schema.validate h
    _(h[:foo]).must_be_nil
    _(h[:bar]).must_equal ''
  end

  it 'should break on bad paramter' do
    _{ Lux.schema { foo req: true, bad_arg: true } }.must_raise ArgumentError
    _{ Lux.schema { num :float, downcase: true } }.must_raise ArgumentError
  end

  it 'shoud load type class' do
    _(Lux.type(:string)).must_equal Lux::Type::StringType
  end
end
