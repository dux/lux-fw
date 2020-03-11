require 'spec_helper'
require 'typero'

Lux.plugin 'api'

class TestApi < ApplicationApi
  def foo
    'foo'
  end

  param :email, :email
  def bar
    'bar'
  end

  def baz
    message 'baz'

    'ok'
  end
end

describe Lux::Api do
  before do
    # Lux.current = nil
  end

  it 'renders foo' do
    expect( TestApi.new.call(:foo)[:data] ).to eq('foo')
  end

  it 'renders bar and checks for email' do
    # expect( TestApi.call(:bar)[:error][:messages][0]).to eq('Email is required')
    # expect( TestApi.call(:bar, email: 'foo@bar.baz')[:data] ).to eq('bar')
  end

  it 'checks full message' do
    full = TestApi.new.call :baz

    expect( full[:data] ).to eq('ok')
    expect( full[:message] ).to eq('baz')
  end
end