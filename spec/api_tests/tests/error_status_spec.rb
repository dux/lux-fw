require 'test_helper'
require_relative '../loader'

describe 'error handling with status codes' do
  describe 'named errors' do
    it 'handles named error code 405' do
      response = GenericApi.render :get_money
      _(response[:success]).must_equal false
      _(response[:error][:messages]).must_include '$ not found'
      _(response[:error][:messages]).must_include '405'
    end
  end

  describe 'unhandled errors' do
    it 'handles unhandled exception with rescue_from :all' do
      $no_error_print = true
      response = GenericApi.render :about
      $no_error_print = false
      _(response[:success]).must_equal false
      _(response[:status]).must_equal 500
      _(response[:error][:messages]).must_include 'Error happens'
    end
  end

  describe 'response_error class method' do
    it 'generates error response from class method' do
      err = GenericApi.response_error('foo bar')
      _(err[:success]).must_equal false
      _(err[:error][:messages]).must_include 'foo bar'
    end
  end

  describe 'error status codes' do
    it 'defaults to 400 for regular errors' do
      response = UserApi.render.login(user: 'wrong', pass: 'wrong')
      _(response[:success]).must_equal false
      _(response[:status]).must_equal 400
    end

    it 'returns 500 for unhandled exceptions' do
      $no_error_print = true
      response = GenericApi.render :about
      $no_error_print = false
      _(response[:status]).must_equal 500
    end
  end

  describe 'error details' do
    it 'includes field-level error details for param validation' do
      response = GenericApi.render :param_test_2, params: {}
      _(response[:success]).must_equal false
      assert response[:error][:details][:foo]
    end
  end
end
