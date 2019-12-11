require 'spec_helper'

describe Crypt do
  it 'simple string' do
    encrypted = Crypt.encrypt('abc')
    expect(encrypted.length).to eq(127)
    decrypted = Crypt.decrypt(encrypted)
    expect(decrypted).to eq('abc')
  end

  it 'should encrypt with password' do
    encrypted = Crypt.encrypt('abc', { password:'foo' })
    expect{Crypt.decrypt(encrypted)}.to raise_error StandardError
    expect(Crypt.decrypt(encrypted, password:'foo')).to eq('abc')
  end

  it 'should encrypt with expiration' do
    enc = 'foo'
    future_str  = Crypt.encrypt(enc, ttl:10)
    expired_str = Crypt.encrypt(enc, ttl:-10)

    expect(Crypt.decrypt(future_str)).to eq(enc)
    expect{ Crypt.decrypt(expired_str) }.to raise_error StandardError
  end
end