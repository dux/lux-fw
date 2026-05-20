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
  let(:doc) { Lux::Api::Introspect.schema(mount_on: '/api') }

  it 'exposes top-level shape' do
    expect(doc.keys).to include(:version, :mount_on, :apis, :errors)
    expect(doc[:version]).to eq('1')
  end

  it 'lists documented apis but skips SysApi' do
    expect(doc[:apis]).to have_key('company')
    expect(doc[:apis]).not_to have_key('sys')
  end

  it 'builds full paths with mount_on' do
    show = doc.dig(:apis, 'company', :member, :show)
    expect(show[:path]).to eq('/api/company/:ref/show')
  end

  it 'preserves http methods and adds POST as default' do
    index = doc.dig(:apis, 'company', :collection, :index)
    expect(index[:http]).to include('POST', 'PUT')
  end

  it 'strips private (_*) opts like :_typero' do
    index = doc.dig(:apis, 'company', :collection, :index)
    expect(index.keys).not_to include(:_typero)
    expect(index[:params]).to be_a(Hash)
    expect(index[:params][:country_id][:type]).to eq(:integer)
  end

  it 'lists named errors' do
    expect(doc[:errors][:named_error]).to eq('Named error example')
  end
end

describe 'Lux::Api::SysApi endpoints' do
  it 'health returns ok' do
    body = sys_call(:health)
    expect(body[:ok]).to eq(true)
    expect(body[:schema_version]).to eq('1')
  end

  it 'schema returns the introspection document' do
    body = sys_call(:schema)
    expect(body[:apis]).to have_key(:company)
    expect(body[:mount_on]).to eq('/api')
  end

  it 'postman returns a v2.1 collection' do
    body = sys_call(:postman)
    expect(body.dig(:info, :schema)).to include('collection/v2.1.0')
    company_group = body[:item].find { |g| g[:name] == 'company' }
    expect(company_group).not_to be_nil
    expect(company_group[:item]).not_to be_empty

    show = company_group[:item].find { |i| i[:name] == 'show' }
    expect(show.dig(:request, :url, :raw)).to eq('http://example.com/api/company/:ref/show')
  end

  it 'openapi returns a 3.0 spec' do
    body = sys_call(:openapi)
    expect(body[:openapi]).to start_with('3.')
    expect(body[:paths]).to have_key(:'/api/company/{ref}/show')
    op = body.dig(:paths, :'/api/company/{ref}/show')
    # show has no explicit allow, so just POST
    expect(op.keys).to include(:post)
  end

  it 'web (no file) returns index.html shell' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    html = Lux::Api::SysApi.render(:web, api_host: host)

    expect(html).to be_a(String)
    expect(html).to include('<script src="?file=boot.js">')
    expect(html).to include('<script fez="?file=/fez/joshua-api.fez">')
    expect(html).to include('<script fez="?file=/fez/joshua-method.fez">')
    expect(html).to include('<script fez="?file=/fez/joshua-runner.fez">')
    expect(html).to include('?file=vendor/postwind.js')
    expect(html).to include('?file=vendor/fez.js')
    expect(html).to include('<joshua-header>')       # header component mount
    expect(html).to include('joshua-header.fez')     # header component registered
    expect(html).to include('<joshua-sidebar>')      # sidebar component mount
    expect(html).to include('joshua-sidebar.fez')    # sidebar component registered
    expect(html).not_to include('<xmp fez=')
  end

  it 'web ?file=/fez/joshua-method.fez returns raw component' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    body = Lux::Api::SysApi.render(:web, api_host: host, params: { file: '/fez/joshua-method.fez' })
    expect(body).to be_a(String)
    expect(body).to include('init(props)')      # script body
    expect(body).to include('anchor()')         # function we defined
    expect(body).not_to include('<xmp')         # raw .fez, no wrapper
  end

  it 'web ?file=boot.js returns the JS file' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    body = Lux::Api::SysApi.render(:web, api_host: host, params: { file: 'boot.js' })
    expect(body).to include('window.joshua')
    expect(body).to include('PostWind.init')
  end

  it 'web treats leading / as web-root, does not escape filesystem' do
    # /etc/passwd is treated as etc/passwd under lib/web/ - just not found
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: '/etc/passwd' }, api_host: host).execute_call
    expect(result[:success]).to eq(false)
    expect(result[:error][:messages].first).to include('extension not allowed')
  end

  it 'web rejects scheme/remote URLs' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: 'https://evil.com/x.js' }, api_host: host).execute_call
    expect(result[:success]).to eq(false)
    expect(result[:error][:messages].first).to include('remote')
  end

  it 'web rejects path traversal' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: '../joshua/sys_api.rb' }, api_host: host).execute_call
    expect(result[:success]).to eq(false)
    expect(result[:error][:messages].first).to include("'..'")
  end

  it 'web rejects disallowed extensions' do
    host = SysMockApiHost.new(path: '/api/sys/web', method: 'GET')
    result = Lux::Api::SysApi.new(:web, params: { file: 'boot.rb' }, api_host: host).execute_call
    expect(result[:success]).to eq(false)
    expect(result[:error][:messages].first).to include('extension not allowed')
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
    expect(status).to eq(302)
    expect(headers['Location']).to eq('/api/sys/web')
  end

  it 'serves sys/schema with Content-Type application/json (CT bug regression)' do
    ApplicationApi.mount_on '/api'
    status, headers, body = Lux::Api.call(rack_env(path: '/api/sys/schema'))
    expect(status).to eq(200)
    expect(headers['Content-Type']).to eq('application/json')
    expect(body.first).to start_with('{')
  end

  it 'serves sys/web with Content-Type text/html' do
    ApplicationApi.mount_on '/api'
    status, headers, body = Lux::Api.call(rack_env(path: '/api/sys/web'))
    expect(status).to eq(200)
    expect(headers['Content-Type']).to start_with('text/html')
    expect(body.first).to include('<joshua-apis>')
    expect(body.first).to include('?file=vendor/postwind.js')
    expect(body.first).to include('?file=vendor/fez.js')
  end
end
