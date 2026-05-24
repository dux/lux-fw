require 'test_helper'
require_relative './fixtures'

describe Lux::Schema do
  before do
    @test  = Test.new
    @rules = TestSchema
  end

  it 'speed min and max should be respected' do
    @test.speed = 5
    errors = @rules.validate(@test)

    _(errors[:speed].length > 5).must_equal true

    @test.speed = 555
    errors = @rules.validate(@test)
    _(errors[:speed].length > 5).must_equal true

    @test.speed = 100
    errors = @rules.validate(@test)
    _(errors[:speed]).must_be_nil
  end

  it 'name should be string' do
    @test.name = :dino
    @rules.valid? @test
    _(@test.name).must_equal 'dino'
  end

  it 'name should allow null name' do
    @test.name = ''
    @rules.valid? @test
    _(@test.name).must_be_nil
  end

  it 'email in array to fail and then pass' do
    @test.emails = ['dux@dux.net', 'duxdux.net']
    errors = @rules.validate(@test)
    _(errors[:emails].include?('@')).must_equal true

    @test.emails = ['dux@dux.net', 'dux2@dix.net']
    errors = @rules.validate(@test)
    _(errors[:emails]).must_be_nil
  end

  it 'label in array to fail' do
    @test.tags = ['foo@bar', 'baz']
    @rules.validate(@test)
    _(@test.tags.first).must_equal 'foobar'
  end

  it 'label in array to pass' do
    @test.tags = ['foo', 'bar']
    @rules.validate(@test)
    _(@test.tags).must_equal ['foo', 'bar']
  end

  it 'should not allow email nil' do
    @test.email     = 'dux@net.hr'
    @test.email_nil = nil
    errors = @rules.validate(@test)
    _(errors[:email_nil]).must_be_nil
    _(errors[:email]).must_be_nil
  end

  it 'age to be 20' do
    @test.age = '20'
    @rules.validate(@test)
    _(@test.age).must_equal 20
  end

  it 'expect eyes to inherite default color' do
    @rules.validate(@test)
    _(@test.eyes).must_equal 'blue'
  end

  it 'raises error when type not found' do
    _{
      Lux.schema do
        kinky  :name
      end
    }.must_raise ArgumentError
  end

  it 'fails on too many array elements' do
    @test.tags = ['foo@bar', 'baz', 123, 344, 444]
    resoult = @rules.validate(@test)
    _(resoult[:tags]).must_equal "Max number of array elements is 3, you have 5"
  end

  it 'tests custom min value' do
    @test.sallary = 500
    resoult = @rules.validate(@test)
    _(resoult[:sallary]).must_equal 'Plata 1000 a ne 500'
  end
end
