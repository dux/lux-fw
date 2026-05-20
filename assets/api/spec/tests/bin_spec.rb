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
  PORT = free_port
  HOST = "http://127.0.0.1:#{PORT}"
  BIN  = File.expand_path('../../bin/lux-api', __dir__)

  before(:all) do
    $no_error_print = true
    @mini = MiniRackServer.new(PORT)
    @server_thread = Thread.new { @mini.start }

    # wait for server to accept connections
    20.times do
      TCPSocket.new('127.0.0.1', PORT).close
      break
    rescue Errno::ECONNREFUSED
      sleep 0.1
    end
  end

  after(:all) do
    @mini&.stop
    @server_thread&.kill
    $no_error_print = false
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
      expect(data).to be_a(Hash)
      expect(data).to have_key('board')
    end

    it 'returns index as YAML' do
      out = lux_api('--yaml')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      expect(data).to be_a(Hash)
      expect(data).to have_key('board')
    end

    it 'returns index as text' do
      out = lux_api('--text')
      expect(out).to include('board:')
      expect(out).to include('collection:')
      expect(out).to include('member:')
    end
  end

  # --- boards ---

  describe 'board/list' do
    it 'returns 2 boards as JSON' do
      data = lux_api_json('board/list')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(2)
      expect(data['data'][0]['name']).to eq('Work')
      expect(data['data'][1]['name']).to eq('Personal')
    end

    it 'returns boards as YAML' do
      out = lux_api('--yaml', 'board/list')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(2)
    end

    it 'returns boards as text' do
      out = lux_api('--text', 'board/list')
      expect(out).to include('success: true')
      expect(out).to include('Work')
      expect(out).to include('Personal')
    end
  end

  # --- board show ---

  describe 'board/:ref/show' do
    it 'shows board 1' do
      data = lux_api_json('board/1/show')
      expect(data['success']).to eq(true)
      expect(data['data']['name']).to eq('Work')
      expect(data['data']['task_count']).to eq(7)
    end

    it 'shows board 2' do
      data = lux_api_json('board/2/show')
      expect(data['success']).to eq(true)
      expect(data['data']['name']).to eq('Personal')
    end

    it 'returns error for unknown board' do
      data = lux_api_json('board/999/show')
      expect(data['success']).to eq(false)
    end
  end

  # --- tasks ---

  describe 'board/:ref/tasks' do
    it 'lists all 7 tasks for board 1' do
      data = lux_api_json('board/1/tasks')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(7)
    end

    it 'lists all 7 tasks for board 2' do
      data = lux_api_json('board/2/tasks')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(7)
    end

    it 'filters active tasks for board 1' do
      data = lux_api_json('board/1/tasks', 'active=true')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(4)
      data['data'].each do |task|
        expect(task['active']).to eq(true)
      end
    end

    it 'filters inactive tasks for board 1' do
      data = lux_api_json('board/1/tasks', 'active=false')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(3)
      data['data'].each do |task|
        expect(task['active']).to eq(false)
      end
    end

    it 'filters active tasks for board 2' do
      data = lux_api_json('board/2/tasks', 'active=true')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(4)
    end

    it 'filters inactive tasks for board 2' do
      data = lux_api_json('board/2/tasks', 'active=false')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(3)
    end

    it 'passes JSON params' do
      data = lux_api_json('board/1/tasks', '{"active":"true"}')
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(4)
    end
  end

  # --- namespace filter ---

  describe 'namespace filter' do
    it 'filters index to a single namespace' do
      data = lux_api_json('board')
      expect(data.keys).to eq(['board'])
      expect(data['board']).to have_key('collection')
      expect(data['board']).to have_key('member')
    end

    it 'works with --yaml format' do
      out = lux_api('--yaml', 'board')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      expect(data.keys).to eq(['board'])
    end

    it 'prints error for unknown namespace' do
      out = lux_api('nonexistent')
      expect(out).to include('Unknown namespace: nonexistent')
      expect(out).to include('Available:')
      expect(out).to include('board')
    end
  end

  # --- output formats on api calls ---

  describe 'output formats' do
    it '--yaml on api call' do
      out = lux_api('--yaml', 'board/1/tasks', 'active=true')
      data = YAML.safe_load(out, permitted_classes: [Symbol])
      expect(data['success']).to eq(true)
      expect(data['data'].size).to eq(4)
    end

    it '--text on api call' do
      out = lux_api('--text', 'board/1/show')
      expect(out).to include('success: true')
      expect(out).to include('name: Work')
    end
  end
end
