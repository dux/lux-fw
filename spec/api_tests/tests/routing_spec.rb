require 'test_helper'
require_relative '../loader'
require 'rack'
require 'stringio'

module Admin
  class UsersApi < ApplicationApi
    define :list do
      proc { 'admin users' }
    end
  end
end

class RoutingPlainApi < ApplicationApi
  define :list do
    proc { 'plain list' }
  end
end

# mounted at / with its own after_auto_mount; ApplicationApi's hook must not leak in
class RootMountedApi < Lux::Api
  mount_on '/'

  after_auto_mount do |parts, opts|
    opts[:params][:hooked] = 'root'
  end
end

class RootMountedPingApi < RootMountedApi
  define :ping do
    proc { params[:hooked] }
  end
end

def routing_env path, method: 'GET'
  {
    'REQUEST_METHOD'  => method,
    'PATH_INFO'       => path,
    'QUERY_STRING'    => '',
    'SERVER_NAME'     => 'example.com',
    'SERVER_PORT'     => '80',
    'HTTP_HOST'       => 'example.com',
    'rack.input'      => StringIO.new(''),
    'rack.url_scheme' => 'http',
    'SCRIPT_NAME'     => ''
  }
end

def routing_call klass, path, method: 'POST'
  status, _headers, body = klass.call(routing_env(path, method: method))
  [status, JSON.parse(body.join, symbolize_names: true)]
end

describe 'Lux::Api URL routing' do
  it 'routes a namespaced class by longest prefix' do
    status, body = routing_call ApplicationApi, '/api/admin/users/list'
    _(status).must_equal 200
    _(body[:data]).must_equal 'admin users'
  end

  it 'still routes a non-namespaced class' do
    status, body = routing_call ApplicationApi, '/api/routing_plain/list'
    _(status).must_equal 200
    _(body[:data]).must_equal 'plain list'
  end

  it 'runs only the mounted class after_auto_mount hook' do
    status, body = routing_call RootMountedApi, '/root_mounted_ping/ping'
    _(status).must_equal 200
    _(body[:data]).must_equal 'root'
  end

  it 'gives sys endpoints the real mount path for an API mounted at /' do
    status, body = routing_call RootMountedApi, '/sys/schema', method: 'GET'
    _(status).must_equal 200
    _(body[:mount_on]).must_equal ''
  end
end

describe 'Lux::Api.opts memo' do
  it 'picks up a define added after the first read, also in subclasses' do
    parent = Class.new(ApplicationApi)
    child  = Class.new(parent)
    _(child.opts.dig(:collection, :late)).must_be_nil
    parent.define(:late) { proc { 1 } }
    _(child.opts.dig(:collection, :late)).must_equal({})
  end

  it 'keeps callback arrays out of the merged opts' do
    _(ApplicationApi.opts.values.all? { _1.is_a?(Hash) }).must_equal true
    _(ApplicationApi.opts.key?(:before_all)).must_equal false
  end
end
