require 'test_helper'
require_relative '../loader'
require 'rack'
require 'stringio'

# Same mock used by sys_spec, repeated here so this file is self-contained.
class FileApiHost
  attr_reader :request, :response

  def initialize(if_none_match: nil)
    env = {
      'REQUEST_METHOD'    => 'GET',
      'PATH_INFO'         => '/api/files/download',
      'QUERY_STRING'      => '',
      'SERVER_NAME'       => 'example.com',
      'SERVER_PORT'       => '80',
      'HTTP_HOST'         => 'example.com',
      'rack.input'        => StringIO.new(''),
      'rack.url_scheme'   => 'http',
      'SCRIPT_NAME'       => ''
    }
    env['HTTP_IF_NONE_MATCH'] = if_none_match if if_none_match

    @request  = Rack::Request.new(env)
    @response = Struct.new(:header, :status).new({}, 200)
  end
end

# Tiny API class with send_file and send_data actions
class FileTestApi < Lux::Api
  documented
  def_registration_strict false

  allow :get
  def grab_file
    send_file __FILE__, name: 'spec.rb', content_type: 'text/x-ruby'
  end

  allow :get
  def grab_data
    send_data 'hello,world', name: 'hi.csv', content_type: 'text/csv'
  end
end

describe Lux::Api::FileResponse do
  it 'send_file sets headers + body + status 200' do
    host = FileApiHost.new
    body = FileTestApi.render(:grab_file, api_host: host)

    _(body).must_be_kind_of String
    _(body).must_include 'class FileTestApi < Lux::Api'

    headers = host.response.header
    _(host.response.status).must_equal 200
    _(headers['Content-Type']).must_equal 'text/x-ruby'
    _(headers['Content-Disposition']).must_equal %(attachment; filename="spec.rb")
    _(headers['Content-Length']).must_equal body.bytesize.to_s
    _(headers['Last-Modified']).must_match(/GMT$/)
    _(headers['ETag']).must_match(/^"[a-f0-9]{40}"$/)
  end

  it 'returns 304 when If-None-Match matches the ETag' do
    # first request to get the ETag
    host1 = FileApiHost.new
    FileTestApi.render(:grab_file, api_host: host1)
    etag = host1.response.header['ETag']

    # second request with the etag - expect 304 + empty body
    host2 = FileApiHost.new(if_none_match: etag)
    body  = FileTestApi.render(:grab_file, api_host: host2)
    _(host2.response.status).must_equal 304
    _(body).must_equal ''
  end

  it 'send_data works without a disk file' do
    host = FileApiHost.new
    body = FileTestApi.render(:grab_data, api_host: host)

    _(body).must_equal 'hello,world'
    _(host.response.header['Content-Type']).must_equal 'text/csv'
    _(host.response.header['Content-Disposition']).must_equal %(attachment; filename="hi.csv")
    _(host.response.header['Last-Modified']).must_be_nil
    _(host.response.header['ETag']).must_match(/^"[a-f0-9]{40}"$/)
  end

  it 'inline: true switches Content-Disposition to inline' do
    api  = FileTestApi.new(:_x, api_host: FileApiHost.new)
    Lux::Api::FileResponse.new(api.instance_variable_get(:@api),
                                    file: __FILE__, inline: true).send
    headers = api.instance_variable_get(:@api).api_host.response.header
    _(headers['Content-Disposition']).must_match(/\Ainline;/)
  end

  it 'download: false switches Content-Disposition to inline' do
    api  = FileTestApi.new(:_x, api_host: FileApiHost.new)
    Lux::Api::FileResponse.new(api.instance_variable_get(:@api),
                             file: __FILE__, download: false).send
    headers = api.instance_variable_get(:@api).api_host.response.header
    _(headers['Content-Disposition']).must_match(/\Ainline;/)
  end

  it 'download: true (or default) forces attachment' do
    api  = FileTestApi.new(:_x, api_host: FileApiHost.new)
    Lux::Api::FileResponse.new(api.instance_variable_get(:@api),
                             file: __FILE__, download: true).send
    headers = api.instance_variable_get(:@api).api_host.response.header
    _(headers['Content-Disposition']).must_match(/\Aattachment;/)
  end

  it 'explicit disposition wins over download/inline shortcuts' do
    api  = FileTestApi.new(:_x, api_host: FileApiHost.new)
    Lux::Api::FileResponse.new(api.instance_variable_get(:@api),
                             file: __FILE__, download: false, disposition: 'attachment').send
    headers = api.instance_variable_get(:@api).api_host.response.header
    _(headers['Content-Disposition']).must_match(/\Aattachment;/)
  end

  it 'raises on missing file' do
    api = FileTestApi.new(:_x, api_host: FileApiHost.new)
    _{
      Lux::Api::FileResponse.new(api.instance_variable_get(:@api),
                               file: '/nonexistent.bin').send
    }.must_raise Lux::Api::Error
  end
end
