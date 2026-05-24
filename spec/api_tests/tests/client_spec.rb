require 'test_helper'
require_relative '../loader'
require_relative '../../lib/lux-api/client'

module HTTP
  def self.post url, opts=nil
    {
      url: url,
      opts: opts
    }.to_json
  end
end

describe 'dev' do
  def api
    @api ||= LuxApiClient.new 'http://localhost:4567/api'
  end

  it 'gets valid collection url' do
    data = api.user.login
    _(data['url']).must_equal 'http://localhost:4567/api/user/login'
    _(data['opts']['form'].keys.length).must_equal 0
  end

  it 'gets valid url with params' do
    data = api.admin__user.login user: 'foo', pass: 'bar'
    _(data['url']).must_equal 'http://localhost:4567/api/admin__user/login'
    _(data['opts']['form'].keys.length).must_equal 2
  end

  it 'gets valid url with id and params' do
    data = api.user(123).show user: 'foo', pass: 'bar'
    _(data['url']).must_equal 'http://localhost:4567/api/user/123/show'
    _(data['opts']['form'].keys.length).must_equal 2
  end
end
