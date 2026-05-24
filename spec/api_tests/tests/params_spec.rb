require 'test_helper'
require_relative '../loader'

describe 'params validation' do
  describe 'existing param tests from GenericApi' do
    it 'passes required params' do
      response = GenericApi.render :param_test_2, params: { foo: 'test' }
      _(response[:success]).must_equal true
      _(response[:data]['foo']).must_equal 'test'
    end

    it 'applies defaults for optional params' do
      response = GenericApi.render :param_test_2, params: { foo: 'test' }
      _(response[:data]['abc']).must_equal 'baz'  # default value (coerced to string)
    end

    it 'allows overriding defaults' do
      response = GenericApi.render :param_test_2, params: { foo: 'test', abc: 'custom' }
      _(response[:data]['abc']).must_equal 'custom'
    end

    it 'fails when required param missing' do
      response = GenericApi.render :param_test_2, params: { abc: 'value' }
      _(response[:success]).must_equal false
      assert response[:error][:details][:foo]
    end
  end

  describe 'CompanyApi params' do
    it 'validates integer type' do
      opts = CompanyApi.opts
      _(opts[:collection][:index][:params][:country_id][:type]).must_equal :integer
    end

    it 'validates boolean type' do
      opts = CompanyApi.opts
      _(opts[:collection][:index][:params][:is_active][:type]).must_equal :boolean
    end

    it 'handles boolean false default in member params' do
      opts = CompanyApi.opts
      _(opts[:member][:index][:params][:is_active][:default]).must_equal false
    end
  end

  describe 'UserApi email validation' do
    it 'rejects bad email in model' do
      response = UserApi.render.update(1, user: { name: 'Test', email: 'bad email' })
      _(response[:success]).must_equal false
    end

    it 'accepts good email in model' do
      response = UserApi.render.update(1, user: { name: 'Test', email: 'good@email.com' })
      _(response[:success]).must_equal true
    end
  end

  describe 'array params' do
    it 'accepts Array type param' do
      opts = GenericApi.opts
      _(opts[:collection][:list_labels][:params][:labels_dup][:type]).must_equal :label
      _(opts[:collection][:list_labels][:params][:labels_dup][:array]).must_equal true
    end

    it 'accepts Set type param stored as array' do
      opts = GenericApi.opts
      _(opts[:collection][:list_labels][:params][:labels_nodup][:type]).must_equal :label
      _(opts[:collection][:list_labels][:params][:labels_nodup][:array]).must_equal true
    end
  end
end
