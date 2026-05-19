require 'spec_helper'
require_relative './fixtures'

describe Lux::Schema do
  before(:all) do
    @test  = Test.new
    @rules = TestSchema
  end

  it 'speed min and max should be respected' do
    @test.speed = 5
    errors = @rules.validate(@test)

    expect(errors[:speed].length > 5).to be_truthy

    @test.speed = 555
    errors = @rules.validate(@test)
    expect(errors[:speed].length > 5).to be_truthy

    @test.speed = 100
    errors = @rules.validate(@test)
    expect(errors[:speed]).to eq(nil)
  end

  it 'name should be string' do
    @test.name = :dino
    @rules.valid? @test
    expect(@test.name).to eq('dino')
  end

  it 'name should allow null name' do
    @test.name = ''
    @rules.valid? @test
    expect(@test.name).to eq(nil)
  end

  it 'email in array to fail and then pass' do
    @test.emails = ['dux@dux.net', 'duxdux.net']
    errors = @rules.validate(@test)
    expect(errors[:emails].include?('@')).to be_truthy

    @test.emails = ['dux@dux.net', 'dux2@dix.net']
    errors = @rules.validate(@test)
    expect(errors[:emails]).to be_nil
  end

  it 'label in array to fail' do
    @test.tags = ['foo@bar', 'baz']
    @rules.validate(@test)
    expect(@test.tags.first).to eq('foobar')
  end

  it 'label in array to pass' do
    @test.tags = ['foo', 'bar']
    @rules.validate(@test)
    expect(@test.tags).to eq(['foo', 'bar'])
  end

  it 'should not allow email nil' do
    @test.email     = 'dux@net.hr'
    @test.email_nil = nil
    errors = @rules.validate(@test)
    expect(errors[:email_nil]).to be_nil
    expect(errors[:email]).to be_nil
  end

  it 'age to be 20' do
    @test.age = '20'
    @rules.validate(@test)
    expect(@test.age).to eq(20)
  end

  it 'expect eyes to inherite default color' do
    @rules.validate(@test)
    expect(@test.eyes).to eq('blue')
  end

  it 'raises error when type not found' do
    expect do
      Lux.schema do
        kinky  :name
      end
    end.to raise_error ArgumentError
  end

  it 'fails on too many array elements' do
    @test.tags = ['foo@bar', 'baz', 123, 344, 444]
    resoult = @rules.validate(@test)
    expect(resoult[:tags]).to eq("Max number of array elements is 3, you have 5")
  end

  it 'tests custom min value' do
    @test.sallary = 500
    resoult = @rules.validate(@test)
    expect(resoult[:sallary]).to eq('Plata 1000 a ne 500')
  end
end
