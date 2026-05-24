require 'test_helper'
require_relative '../loader'

describe 'dev' do
  it 'calls login trough proxy' do
    response = UserApi.render.login(user: 'foo', pass: 'bar')
    _(response[:success]).must_equal true
  end

  it 'calls login trough proxy' do
    response = CompanyApi.render.show(1)
    _(response[:success]).must_equal true
    _(response[:data]).must_equal 'ACME corp'
  end
end
