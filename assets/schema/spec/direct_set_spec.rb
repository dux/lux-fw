require 'spec_helper'
require_relative './fixtures'

describe Lux do
  before(:all) do
    @test  = Test.new
    @rules = TestSchema
  end

  it 'expects email in right format' do
    email = 'dUX@NET.hr'
    expect(Lux.type(:email, email)).to eq(email.downcase)
  end

  it 'expects email to raise an error' do
    email = 'dUXNET.hr'
    expect { Lux.type(:email, email) }.to raise_error TypeError
  end

  it 'expects email to raise an error in block' do
    email = 'dUXNET.hr'
    Lux.type(:email, email) { |e| @error = e.message }
    expect(@error).to eq('is missing @')
  end
end
