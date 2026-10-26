require 'test_helper'

require_relative '../load/lib/application_api'

unless defined?(User)
  class User
    class << self
      attr_accessor :current
    end
  end
end

unless defined?(UserSession)
  class UserSession
    def self.api_key_load(_token) = nil
  end
end

class SpecGuardedApi < ApplicationApi
  define :secret do
    proc { 'ok' }
  end
end

describe 'ApplicationApi auth' do
  it 'answers an anonymous call to a non-unsafe endpoint with 401' do
    User.current = nil
    res = SpecGuardedApi.render :secret
    _(res[:success]).must_equal false
    _(res[:status]).must_equal 401
  end
end
