require_relative '../loader'

# Mock api_host with configurable request method
class MockApiHost
  attr_reader :request

  def initialize(method)
    @request = Struct.new(:request_method, :ip).new(method, '127.0.0.1')
  end
end

describe 'HTTP method restrictions' do
  before(:all) do
    class HttpTestApi < ApplicationApi
      # No allow = POST only
      define :post_only do
        proc { 'post_only_result' }
      end

      # GET allowed
      define get: :get_allowed do
        proc { 'get_allowed_result' }
      end

      # Multiple methods allowed
      define [:get, :put] => :multi_allowed do
        proc { 'multi_allowed_result' }
      end

      # Using allow inside block
      define :explicit_allow do
        allow :get, :delete
        proc { 'explicit_allow_result' }
      end
    end
  end

  context 'allow directive storage' do
    it 'stores allow DELETE on method' do
      opts = UserApi.opts
      expect(opts[:collection][:call_me_in_child][:allow]).to eq(['DELETE'])
    end

    it 'stores allow PUT on CompanyApi collection index' do
      opts = CompanyApi.opts
      expect(opts[:collection][:index][:allow]).to eq(['PUT'])
    end

    it 'defaults to nil (POST) when no allow specified' do
      opts = HttpTestApi.opts
      expect(opts[:collection][:post_only][:allow]).to be_nil
    end

    it 'stores single method as array' do
      opts = HttpTestApi.opts
      expect(opts[:collection][:get_allowed][:allow]).to eq(['GET'])
    end

    it 'stores multiple methods as array' do
      opts = HttpTestApi.opts
      expect(opts[:collection][:multi_allowed][:allow]).to eq(['GET', 'PUT'])
    end

    it 'stores explicit allow :get, :delete as array' do
      opts = HttpTestApi.opts
      expect(opts[:collection][:explicit_allow][:allow]).to eq(['GET', 'DELETE'])
    end
  end

  context 'HTTP method enforcement' do
    it 'allows POST by default when no allow specified' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('POST')
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('post_only_result')
    end

    it 'rejects GET when only POST allowed' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('GET')
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to include('GET request is not allowed')
    end

    it 'rejects PUT when only POST allowed' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('PUT')
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to include('PUT request is not allowed')
    end

    it 'allows GET when get: specified' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('GET')
      expect(response[:success]).to eq(true)
    end

    it 'allows POST when get: specified (POST always allowed)' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('POST')
      expect(response[:success]).to eq(true)
    end

    it 'rejects DELETE when only GET allowed' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('DELETE')
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to include('DELETE request is not allowed')
    end

    it 'allows GET when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('GET')
      expect(response[:success]).to eq(true)
    end

    it 'allows PUT when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('PUT')
      expect(response[:success]).to eq(true)
    end

    it 'allows POST when [:get, :put] specified (POST always allowed)' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('POST')
      expect(response[:success]).to eq(true)
    end

    it 'rejects DELETE when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('DELETE')
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to include('DELETE request is not allowed')
    end

    it 'allows GET when allow :get, :delete specified' do
      response = HttpTestApi.render :explicit_allow, api_host: MockApiHost.new('GET')
      expect(response[:success]).to eq(true)
    end

    it 'allows DELETE when allow :get, :delete specified' do
      response = HttpTestApi.render :explicit_allow, api_host: MockApiHost.new('DELETE')
      expect(response[:success]).to eq(true)
    end

    it 'rejects PUT when allow :get, :delete specified' do
      response = HttpTestApi.render :explicit_allow, api_host: MockApiHost.new('PUT')
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to include('PUT request is not allowed')
    end
  end

  context 'development mode bypasses restrictions' do
    it 'allows any method in development mode' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('DELETE'), development: true
      expect(response[:success]).to eq(true)
    end
  end
end
