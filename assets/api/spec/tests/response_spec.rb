require_relative '../loader'

describe Lux::Api::Response do
  it 'creates success response with data' do
    response = GenericApi.render :all_ok
    expect(response[:success]).to eq(true)
    expect(response[:data]).to eq('ok')
    expect(response[:status]).to eq(200)
  end

  it 'adds meta data via response[]=' do
    response = CompanyApi.render :index, id: 1, params: { name: 'Test' }
    expect(response[:meta][:ip]).to eq('1.2.3.4')
  end

  it 'adds message to response' do
    response = CompanyApi.render :index, id: 1, params: { name: 'Test' }
    expect(response[:message]).to eq('all ok')
  end

  it 'returns nil data when method returns nil' do
    class NilDataApi < ApplicationApi
      def return_nil
        nil
      end
    end
    response = NilDataApi.render :return_nil
    expect(response[:success]).to eq(true)
    expect(response.key?(:data)).to eq(false)
  end

  it 'returns hash data correctly' do
    response = GenericApi.render :param_test_1, params: { foo: 'bar' }
    expect(response[:data]).to eq({ foo: 'bar' })
  end

  it 'handles response.data= assignment' do
    class DataAssignApi < ApplicationApi
      def assign_data
        response.data = { custom: 'value' }
        'ignored'
      end
    end
    response = DataAssignApi.render :assign_data
    expect(response[:data]).to eq({ custom: 'value' })
  end
end
