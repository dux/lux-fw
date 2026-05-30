require 'test_helper'
require_relative '../loader'

# Mock api_host with configurable request method
class MockApiHost
  attr_reader :request

  def initialize(method)
    @request = Struct.new(:request_method, :ip).new(method, '127.0.0.1')
  end
end

describe 'HTTP method restrictions' do
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

  describe 'allow directive storage' do
    it 'stores allow DELETE on method' do
      opts = UserApi.opts
      _(opts[:collection][:call_me_in_child][:allow]).must_equal ['DELETE']
    end

    it 'stores allow PUT on CompanyApi collection index' do
      opts = CompanyApi.opts
      _(opts[:collection][:index][:allow]).must_equal ['PUT']
    end

    it 'defaults to nil (POST) when no allow specified' do
      opts = HttpTestApi.opts
      _(opts[:collection][:post_only][:allow]).must_be_nil
    end

    it 'stores single method as array' do
      opts = HttpTestApi.opts
      _(opts[:collection][:get_allowed][:allow]).must_equal ['GET']
    end

    it 'stores multiple methods as array' do
      opts = HttpTestApi.opts
      _(opts[:collection][:multi_allowed][:allow]).must_equal ['GET', 'PUT']
    end

    it 'stores explicit allow :get, :delete as array' do
      opts = HttpTestApi.opts
      _(opts[:collection][:explicit_allow][:allow]).must_equal ['GET', 'DELETE']
    end
  end

  describe 'HTTP method enforcement' do
    it 'allows POST by default when no allow specified' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('POST')
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'post_only_result'
    end

    it 'rejects GET when only POST allowed' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('GET')
      _(response[:success]).must_equal false
      _(response[:error][:messages].first).must_include 'GET request is not allowed'
    end

    it 'rejects PUT when only POST allowed' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('PUT')
      _(response[:success]).must_equal false
      _(response[:error][:messages].first).must_include 'PUT request is not allowed'
    end

    it 'allows GET when get: specified' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('GET')
      _(response[:success]).must_equal true
    end

    it 'allows OPTIONS when get: specified' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('OPTIONS')
      _(response[:success]).must_equal true
    end

    it 'allows POST when get: specified (POST always allowed)' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('POST')
      _(response[:success]).must_equal true
    end

    it 'rejects DELETE when only GET allowed' do
      response = HttpTestApi.render :get_allowed, api_host: MockApiHost.new('DELETE')
      _(response[:success]).must_equal false
      _(response[:error][:messages].first).must_include 'DELETE request is not allowed'
    end

    it 'allows GET when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('GET')
      _(response[:success]).must_equal true
    end

    it 'allows OPTIONS when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('OPTIONS')
      _(response[:success]).must_equal true
    end

    it 'allows PUT when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('PUT')
      _(response[:success]).must_equal true
    end

    it 'allows POST when [:get, :put] specified (POST always allowed)' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('POST')
      _(response[:success]).must_equal true
    end

    it 'rejects DELETE when [:get, :put] specified' do
      response = HttpTestApi.render :multi_allowed, api_host: MockApiHost.new('DELETE')
      _(response[:success]).must_equal false
      _(response[:error][:messages].first).must_include 'DELETE request is not allowed'
    end

    it 'allows GET when allow :get, :delete specified' do
      response = HttpTestApi.render :explicit_allow, api_host: MockApiHost.new('GET')
      _(response[:success]).must_equal true
    end

    it 'allows DELETE when allow :get, :delete specified' do
      response = HttpTestApi.render :explicit_allow, api_host: MockApiHost.new('DELETE')
      _(response[:success]).must_equal true
    end

    it 'rejects PUT when allow :get, :delete specified' do
      response = HttpTestApi.render :explicit_allow, api_host: MockApiHost.new('PUT')
      _(response[:success]).must_equal false
      _(response[:error][:messages].first).must_include 'PUT request is not allowed'
    end
  end

  describe 'development mode bypasses restrictions' do
    it 'allows any method in development mode' do
      response = HttpTestApi.render :post_only, api_host: MockApiHost.new('DELETE'), development: true
      _(response[:success]).must_equal true
    end
  end
end
