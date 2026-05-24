require 'test_helper'
require_relative '../loader'

describe Lux::Api do
  def company_name
    @company_name ||= 'acme gmbh'
  end

  describe 'company' do
    it 'gets valid collection url' do
      response = CompanyApi.render.update(1, company: { name: company_name, address: 'nowhere 123' })
      _(response[:data]['name']).must_equal company_name
    end

    it 'strips out undefined fields' do
      response = CompanyApi.render.update(1, company: { name: company_name, not_defined: 'nowhere 123' })
      _(response[:data]['name']).must_equal company_name
      _(response[:data]['address']).must_be_nil
      _(response[:data]['not_defined']).must_be_nil
    end

    it 'allows alternative method define' do
      response = CompanyApi.render.foo(1, { bar: 3 })
      _(response[:data]).must_equal 9
    end
  end

  describe 'user' do
    it 'rejects bad email in user model' do
      response = UserApi.render.update(1, user: { name: company_name, email: 'bad email' })
      _(response[:success]).must_equal false
    end

    it 'passes with good email' do
      response = UserApi.render.update(1, user: { name: company_name, email: 'better@email.com' })
      _(response[:success]).must_equal true
    end
  end

  describe 'parent - child' do
    it 'test collection' do
      response = UserApi.render.call_me_in_child
      _(response[:data]).must_equal 4690
    end

    it 'test member' do
      response = UserApi.render.call_me_in_child(1)
      _(response[:data]).must_equal 2468
    end
  end
end
