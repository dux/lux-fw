require 'test_helper'
require_relative '../loader'

# Covers the class-level `auth` hook and the `response()` helper guard.

describe 'auth hook' do
  before do
    unless defined?(AuthHookApi)
      class AuthHookApi < ApplicationApi
        auth do |bearer|
          bearer == 'good' ? 'alice' : response.error('auth required', status: 401)
        end

        define :who do
          proc { user }   # framework helper -> @current_user (auth hook return)
        end

        unsafe
        define :ping do
          proc { 'pong' }
        end
      end
    end
  end

  it 'rejects a non-unsafe endpoint when the hook errors' do
    res = AuthHookApi.render :who
    _(res[:success]).must_equal false
    _(res[:status]).must_equal 401
  end

  it 'passes through with a valid bearer and exposes what the hook set' do
    res = AuthHookApi.render :who, bearer: 'good'
    _(res[:success]).must_equal true
    _(res[:data]).must_equal 'alice'
  end

  it 'skips the hook for unsafe endpoints' do
    res = AuthHookApi.render :ping
    _(res[:success]).must_equal true
    _(res[:data]).must_equal 'pong'
  end
end

describe 'response() helper guard' do
  before do
    unless defined?(ResponseGuardApi)
      class ResponseGuardApi < ApplicationApi
        unsafe
        define :ct_no_block do
          proc { response('text/csv') }
        end
      end
    end
  end

  it 'raises (not silently sets body) when response(content_type) gets no block' do
    $no_error_print = true
    res = ResponseGuardApi.render :ct_no_block
    $no_error_print = false

    # the raise is funneled through rescue_from :all -> error response, NOT a
    # 200 whose body is the string "text/csv"
    _(res[:success]).must_equal false
    _(res[:data]).must_be_nil
  end
end
