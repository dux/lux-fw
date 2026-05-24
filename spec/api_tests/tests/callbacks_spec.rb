require 'test_helper'
require_relative '../loader'

describe 'before/after callbacks' do
  describe 'global callbacks' do
    it 'executes before callback' do
      # ApplicationApi sets @_time in before block
      response = GenericApi.render :all_ok
      _(response[:success]).must_equal true
    end

    it 'executes after callback' do
      # ApplicationApi sets :ip in after block
      response = GenericApi.render :all_ok
      _(response[:meta][:ip]).must_equal '1.2.3.4'
    end
  end

  describe 'member-specific callbacks' do
    it 'executes member before callback' do
      # ModelApi member before loads @model
      response = CompanyApi.render :show, id: 1
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'ACME corp'
    end

    it 'member before can reject request' do
      # ModelApi member before returns error for invalid id
      response = CompanyApi.render :show, id: 999
      _(response[:success]).must_equal false
      _(response[:error][:messages].first).must_equal 'Model not found'
    end
  end

  describe 'callback execution order' do
    it 'executes callbacks in ancestor order' do
      # CompanyApi -> ModelApi -> ApplicationApi
      # before_all from ApplicationApi runs first
      # then before_member from ModelApi
      response = CompanyApi.render :index, id: 1, params: { name: 'Test' }
      _(response[:success]).must_equal true
      _(response[:meta][:ip]).must_equal '1.2.3.4'  # from ApplicationApi after
    end
  end

  describe 'collection callbacks' do
    it 'does not run member before for collection methods' do
      # collection methods should not require @model
      response = CompanyApi.render :info
      _(response[:success]).must_equal true
      _(response[:data][:countries_in_index]).must_equal 123
    end
  end
end
