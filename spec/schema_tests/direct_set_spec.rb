require 'test_helper'
require_relative './fixtures'

describe Lux do
  before do
    @test  = Test.new
    @rules = TestSchema
  end

  it 'expects email in right format' do
    email = 'dUX@NET.hr'
    _(Lux.type(:email, email)).must_equal email.downcase
  end

  it 'expects email to raise an error' do
    email = 'dUXNET.hr'
    _{ Lux.type(:email, email) }.must_raise TypeError
  end

  it 'expects email to raise an error in block' do
    email = 'dUXNET.hr'
    Lux.type(:email, email) { |e| @error = e.message }
    _(@error).must_equal 'is missing @'
  end
end
