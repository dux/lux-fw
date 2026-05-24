require 'test_helper'
require_relative '../loader'
require 'rack'
require 'stringio'

# minimal rack-style api_host the sys generators expect
class SysMockApiHost
  attr_reader :request, :response

  def initialize(path:, method: 'GET')
    env = {
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
    @request  = Rack::Request.new(env)
    @response = Struct.new(:header, :status).new({}, 200)
  end
end

def sys_call(action)
  host = SysMockApiHost.new(path: "/api/sys/#{action}", method: 'GET')
  raw  = Lux::Api::SysApi.render(action, api_host: host)
  JSON.parse(raw, symbolize_names: true)
end

describe Lux::Api::Introspect do
  # pin mount_on so the test is robust to OPTS[:api][:mount_on] global
  # being clobbered by other fixtures (e.g. kitchen_sink sets /kapi)
  def doc
    @doc ||= Lux::Api::Introspect.schema(mount_on: '/api')
  end

  it 'exposes top-level shape' do
    _(doc.keys).must_include :version
    _(doc.keys).must_include :mount_on
    _(doc.keys).must_include :apis
    _(doc.keys).must_include :errors
    _(doc[:version]).must_equal '1'
  end

  it 'lists documented apis but skips SysApi' do
    _(doc[:apis]).must_include 'company'
    _(doc[:apis].key?('sys')).must_equal false
  end

  it 'builds full paths with mount_on' do
    show = doc.dig(:apis, 'company', :member, :show)
    _(show[:path]).must_equal '/api/company/:ref/show'
  end

  it 'preserves http methods and adds POST as default' do
    index = doc.dig(:apis, 'company', :collection, :index)
    _(index[:http]).must_include 'POST'
    _(index[:http]).must_include 'PUT'
  end

  it 'strips private (_*) opts like :_typero' do
    index = doc.dig(:apis, 'company', :collection, :index)
    _(index.keys.include?(:_typero)).must_equal false
    _(index[:params]).must_be_kind_of Hash
    _(index[:params][:country_id][:type]).must_equal :integer
  end

  it 'lists named errors' do
    _(doc[:errors][:named_error]).must_equal 'Named error example'
  end
end

describe 'Lux::Api::SysApi endpoints' do
  it 'health returns ok' do
    body = sys_call(:health)
    _(body[:ok]).must_equal true
    _(body[:schema_version]).must_equal '1'
  end

  it 'schema returns the introspection document' do
    body = sys_call(:schema)
    _(body[:apis]).must_include :company
    _(body[:mount_on]).must_equal '/api'
  end

  it 'postman returns a v2.1 collection' do
    body = sys_call(:postman)
    _(body.dig(:info, :schema)).must_match(/collection\/v2\.1\.0/)
    company_group = body[:item].find { |g| g[:name] == 'company' }
    refute_nil company_group
    refute_empty company_group[:item]

    show = company_group[:item].find { |i| i[:name] == 'show' }
    _(show.dig(:request, :url, :raw)).must_equal 'http://example.com/api/company/:ref/show'
  end

  it 'openapi returns a 3.0 spec' do
    body = sys_call(:openapi)
    _(body[:openapi]).must_match(/\A3\./)
    _(body[:paths]).must_include :'/api/company/{ref}/show'
    op = body.dig(:paths, :'/api/company/{ref}/show')
    # show has no explicit allow, so just POST
    _(op.keys).must_include :post
  end

  it 'web (no file) returns index.html shell' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    html = Lux::Api::SysApi.render(:web, api_host: host)

    _(html).must_be_kind_of String
    _(html).must_include '<script src="?file=boot.js">'
    _(html).must_include '<script fez="?file=/fez/lux-api.fez">'
    _(html).must_include '<script fez="?file=/fez/lux-api-method.fez">'
    _(html).must_include '<script fez="?file=/fez/lux-api-runner.fez">'
    _(html).must_include '?file=vendor/postwind.js'
    _(html).must_include '?file=vendor/fez.js'
    _(html).must_include '<lux-api-header>'       # header component mount
    _(html).must_include 'lux-api-header.fez'     # header component registered
    _(html).must_include '<lux-api-sidebar>'      # sidebar component mount
    _(html).must_include 'lux-api-sidebar.fez'    # sidebar component registered
    _(html.include?('<xmp fez=')).must_equal false
  end

  it 'web ?file=/fez/lux-api-method.fez returns raw component' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    body = Lux::Api::SysApi.render(:web, api_host: host, params: { file: '/fez/lux-api-method.fez' })
    _(body).must_be_kind_of String
    _(body).must_include 'init(props)'      # script body
    _(body).must_include 'anchor()'         # function we defined
    _(body.include?('<xmp')).must_equal false # raw .fez, no wrapper
  end

  it 'web ?file=boot.js returns the JS file' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    body = Lux::Api::SysApi.render(:web, api_host: host, params: { file: 'boot.js' })
    _(body).must_include 'window.lux_api'
    _(body).must_include 'PostWind.init'
  end

  it 'web treats leading / as web-root, does not escape filesystem' do
    # /etc/passwd is treated as etc/passwd under lib/web/ - just not found
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: '/etc/passwd' }, api_host: host).execute_call
    _(result[:success]).must_equal false
    _(result[:error][:messages].first).must_include 'extension not allowed'
  end

  it 'web rejects scheme/remote URLs' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: 'https://evil.com/x.js' }, api_host: host).execute_call
    _(result[:success]).must_equal false
    _(result[:error][:messages].first).must_include 'remote'
  end

  it 'web rejects path traversal' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: '../lux-api/sys_api.rb' }, api_host: host).execute_call
    _(result[:success]).must_equal false
    _(result[:error][:messages].first).must_include "'..'"
  end

  it 'web rejects disallowed extensions' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: 'boot.rb' }, api_host: host).execute_call
    _(result[:success]).must_equal false
    _(result[:error][:messages].first).must_include 'extension not allowed'
  end
end

describe 'Lux::Api rack call' do
  def rack_env(path:, method: 'GET')
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

  it 'redirects the mount root GET to /<mount>/sys/web' do
    # ApplicationApi sets mount_on '/api'
    ApplicationApi.mount_on '/api'  # ensure for this test (kitchen_sink may clobber)
    status, headers, _ = Lux::Api.call(rack_env(path: '/api'))
    _(status).must_equal 302
    _(headers['Location']).must_equal '/api/sys/web'
  end

  it 'serves sys/schema with Content-Type application/json (CT bug regression)' do
    ApplicationApi.mount_on '/api'
    status, headers, body = Lux::Api.call(rack_env(path: '/api/sys/schema'))
    _(status).must_equal 200
    _(headers['Content-Type']).must_equal 'application/json'
    _(body.first).must_match(/\A\{/)
  end

  it 'serves sys/web with Content-Type text/html' do
    ApplicationApi.mount_on '/api'
    status, headers, body = Lux::Api.call(rack_env(path: '/api/sys/web'))
    _(status).must_equal 200
    _(headers['Content-Type']).must_match(/\Atext\/html/)
    _(body.first).must_include '<lux-api-apis>'
    _(body.first).must_include '?file=vendor/postwind.js'
    _(body.first).must_include '?file=vendor/fez.js'
  end
end
