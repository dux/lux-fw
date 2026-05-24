require 'test_helper'
require_relative '../loader'
require 'rack'
require 'socket'
require 'yaml'
require 'uri'
require 'stringio'

# Mock response with .header (what Lux::Api's auto_mount expects)
class BinTestResponse
  attr_reader :header
  attr_accessor :status

  def initialize
    @header = {}
    @status = 200
  end
end

# Mock api_host that auto_mount expects (needs .request and .response)
class BinTestApiHost
  attr_reader :request, :response

  def initialize(env)
    @request  = Rack::Request.new(env)
    @response = BinTestResponse.new
  end
end

# Minimal HTTP server that delegates to ApplicationApi.auto_mount
class MiniRackServer
  def initialize(port)
    @port = port
  end

  def start
    @server = TCPServer.new('127.0.0.1', @port)

    loop do
      client = @server.accept
      begin
        handle(client)
      rescue => e
        msg = "#{e.message}\n#{e.backtrace.first(3).join("\n")}"
        client.print "HTTP/1.1 500 Error\r\nContent-Type: text/plain\r\nContent-Length: #{msg.bytesize}\r\n\r\n#{msg}"
      ensure
        client.close rescue nil
      end
    rescue IOError
      break
    end
  end

  def stop
    @server&.close
  end

  private

  def handle(client)
    request_line = client.gets
    return unless request_line

    method, path, _ = request_line.split(' ')
    headers = {}

    while (line = client.gets) && line != "\r\n"
      key, val = line.split(': ', 2)
      headers[key.strip] = val.strip
    end

    body = ''
    if (len = headers['Content-Length']&.to_i) && len > 0
      body = client.read(len)
    end

    env = build_env(method, path, headers, body)
    host = BinTestApiHost.new(env)

    data = ApplicationApi.auto_mount(
      api_host: host,
      mount_on: "http://127.0.0.1:#{@port}/",
      development: true
    )

    if data.is_a?(Hash)
      resp_body = data.to_json
      content_type = 'application/json'
    else
      resp_body = data.to_s
      content_type = 'text/html'
    end

    client.print "HTTP/1.1 200 OK\r\n"
    client.print "Content-Type: #{content_type}\r\n"
    client.print "Content-Length: #{resp_body.bytesize}\r\n"
    client.print "\r\n"
    client.print resp_body
  end

  def build_env(method, path, headers, body)
    uri = URI(path)

    env = {
      'REQUEST_METHOD'    => method,
      'PATH_INFO'         => uri.path,
      'QUERY_STRING'      => uri.query || '',
      'SERVER_NAME'       => '127.0.0.1',
      'SERVER_PORT'       => @port.to_s,
      'HTTP_HOST'         => "127.0.0.1:#{@port}",
      'rack.input'        => StringIO.new(body),
      'rack.url_scheme'   => 'http',
      'SCRIPT_NAME'       => '',
    }

    headers.each do |key, val|
      rack_key = 'HTTP_' + key.upcase.tr('-', '_')
      env[rack_key] = val
    end

    env['CONTENT_TYPE']   = headers['Content-Type']   if headers['Content-Type']
    env['CONTENT_LENGTH'] = headers['Content-Length']  if headers['Content-Length']
    env
  end
end

# find a free port
def free_port
  s = TCPServer.new('127.0.0.1', 0)
  port = s.addr[1]
  s.close
  port
end

describe 'bin/lux-api' do
  PORT ||= free_port
  HOST ||= "http://127.0.0.1:#{PORT}"
  BIN  ||= File.expand_path('../../../bin/lux-api', __dir__)

  before do
    unless $bin_server_started
      $no_error_print = true
      $bin_mini = MiniRackServer.new(PORT)
      $bin_server_thread = Thread.new { $bin_mini.start }

      # wait for server to accept connections
      20.times do
        TCPSocket.new('127.0.0.1', PORT).close
        break
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end

      Minitest.after_run do
        $bin_mini&.stop
        $bin_server_thread&.kill
        $no_error_print = false
      end

      $bin_server_started = true
    end
  end

  def lux_api(*args)
    cmd = args.map { |a| a.include?(' ') || a.include?('{') ? "'#{a}'" : a }.join(' ')
    # capture stdout + stderr, but strip bundler/rubygems warnings that pollute output
    out = `LUX_API_HOST=#{HOST} ruby #{BIN} #{cmd} 2>&1`
    out.lines.reject { |l| l =~ %r{warning: (already initialized|previous definition)} || l =~ %r{rubygems_ext\.rb|platform\.rb} }.join
  end

  def lux_api_json(*args)
    out = lux_api(*args)
    JSON.parse(out)
  rescue JSON::ParserError => e
    raise "Failed to parse JSON from bin/lux-api output:\n#{out}\n#{e.message}"
  end

  # --- index ---

  describe 'index (no args)' do
    it 'returns the full API index as JSON' do
      data = lux_api_json
      _(data).must_be_kind_of Hash
      _(data).must_include 'board'
    end

    it 'returns index as YAML' do
      out = lux_api('--yaml')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      _(data).must_be_kind_of Hash
      _(data).must_include 'board'
    end

    it 'returns index as text' do
      out = lux_api('--text')
      _(out).must_include 'board:'
      _(out).must_include 'collection:'
      _(out).must_include 'member:'
    end
  end

  # --- boards ---

  describe 'board/list' do
    it 'returns 2 boards as JSON' do
      data = lux_api_json('board/list')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 2
      _(data['data'][0]['name']).must_equal 'Work'
      _(data['data'][1]['name']).must_equal 'Personal'
    end

    it 'returns boards as YAML' do
      out = lux_api('--yaml', 'board/list')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 2
    end

    it 'returns boards as text' do
      out = lux_api('--text', 'board/list')
      _(out).must_include 'success: true'
      _(out).must_include 'Work'
      _(out).must_include 'Personal'
    end
  end

  # --- board show ---

  describe 'board/:ref/show' do
    it 'shows board 1' do
      data = lux_api_json('board/1/show')
      _(data['success']).must_equal true
      _(data['data']['name']).must_equal 'Work'
      _(data['data']['task_count']).must_equal 7
    end

    it 'shows board 2' do
      data = lux_api_json('board/2/show')
      _(data['success']).must_equal true
      _(data['data']['name']).must_equal 'Personal'
    end

    it 'returns error for unknown board' do
      data = lux_api_json('board/999/show')
      _(data['success']).must_equal false
    end
  end

  # --- tasks ---

  describe 'board/:ref/tasks' do
    it 'lists all 7 tasks for board 1' do
      data = lux_api_json('board/1/tasks')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 7
    end

    it 'lists all 7 tasks for board 2' do
      data = lux_api_json('board/2/tasks')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 7
    end

    it 'filters active tasks for board 1' do
      data = lux_api_json('board/1/tasks', 'active=true')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 4
      data['data'].each do |task|
        _(task['active']).must_equal true
      end
    end

    it 'filters inactive tasks for board 1' do
      data = lux_api_json('board/1/tasks', 'active=false')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 3
      data['data'].each do |task|
        _(task['active']).must_equal false
      end
    end

    it 'filters active tasks for board 2' do
      data = lux_api_json('board/2/tasks', 'active=true')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 4
    end

    it 'filters inactive tasks for board 2' do
      data = lux_api_json('board/2/tasks', 'active=false')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 3
    end

    it 'passes JSON params' do
      data = lux_api_json('board/1/tasks', '{"active":"true"}')
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 4
    end
  end

  # --- namespace filter ---

  describe 'namespace filter' do
    it 'filters index to a single namespace' do
      data = lux_api_json('board')
      _(data.keys).must_equal ['board']
      _(data['board']).must_include 'collection'
      _(data['board']).must_include 'member'
    end

    it 'works with --yaml format' do
      out = lux_api('--yaml', 'board')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      _(data.keys).must_equal ['board']
    end

    it 'prints error for unknown namespace' do
      out = lux_api('nonexistent')
      _(out).must_include 'Unknown namespace: nonexistent'
      _(out).must_include 'Available:'
      _(out).must_include 'board'
    end
  end

  # --- output formats on api calls ---

  describe 'output formats' do
    it '--yaml on api call' do
      out = lux_api('--yaml', 'board/1/tasks', 'active=true')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      _(data['success']).must_equal true
      _(data['data'].size).must_equal 4
    end

    it '--text on api call' do
      out = lux_api('--text', 'board/1/show')
      _(out).must_include 'success: true'
      _(out).must_include 'name: Work'
    end
  end
end
