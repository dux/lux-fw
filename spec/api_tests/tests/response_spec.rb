require 'test_helper'
require_relative '../loader'

describe Lux::Api::Response do
  it 'creates success response with data' do
    response = GenericApi.render :all_ok
    _(response[:success]).must_equal true
    _(response[:data]).must_equal 'ok'
    _(response[:status]).must_equal 200
  end

  it 'adds meta data via response[]=' do
    response = CompanyApi.render :index, id: 1, params: { name: 'Test' }
    _(response[:meta][:ip]).must_equal '1.2.3.4'
  end

  it 'adds message to response' do
    response = CompanyApi.render :index, id: 1, params: { name: 'Test' }
    _(response[:message]).must_equal 'all ok'
  end

  it 'returns nil data when method returns nil' do
    class NilDataApi < ApplicationApi
      define :return_nil do
        proc { nil }
      end
    end
    response = NilDataApi.render :return_nil
    _(response[:success]).must_equal true
    _(response.key?(:data)).must_equal false
  end

  it 'returns hash data correctly' do
    response = GenericApi.render :param_test_1, params: { foo: 'bar' }
    _(response[:data]).must_equal({ 'foo' => 'bar' })
  end

  it 'handles response.data= assignment' do
    class DataAssignApi < ApplicationApi
      define :assign_data do
        proc do
          response.data = { custom: 'value' }
          'ignored'
        end
      end
    end
    response = DataAssignApi.render :assign_data
    _(response[:data]).must_equal({ custom: 'value' })
  end
end
