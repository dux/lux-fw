# Vibe::Server routes through Rack::MockRequest: page, health, git api on a tmp
# repo, and the /oc proxy against a stub upstream (plain TCPServer, no extra gems).
#
#   cd ~/dev/gems/lux-fw && LUX_ENV=test bundle exec rspec plugins/vibe/spec

require 'tmpdir'
require 'fileutils'
require 'socket'
require 'rack/mock'

begin
  require_relative '../lib/vibe/server'
rescue LoadError => e
  warn "vibe server spec skipped: #{e.message}"
  return
end

RSpec.describe Vibe::Server do
  def req
    Rack::MockRequest.new(described_class)
  end

  def json_post path, body
    req.post(path, input: JSON.generate(body), 'CONTENT_TYPE' => 'application/json')
  end

  # one-shot http stub: records request line + body, answers with a json body
  def with_upstream
    server = TCPServer.new('127.0.0.1', 0)
    port   = server.addr[1]
    seen   = {}
    thread = Thread.new do
      client = server.accept
      seen[:line] = client.gets
      headers = {}
      while (line = client.gets) && line.strip != ''
        k, v = line.split(':', 2)
        headers[k.strip.downcase] = v.to_s.strip
      end
      seen[:body] = headers['content-length'] ? client.read(headers['content-length'].to_i) : ''
      payload = '{"ok":true}'
      client.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}"
      client.close
    end
    ENV['VIBE_OC_URL'] = "http://127.0.0.1:#{port}"
    yield seen
    thread.join(3)
  ensure
    ENV.delete 'VIBE_OC_URL'
    server&.close
  end

  before do
    @tmp  = Dir.mktmpdir('vibe-srv')
    @work = File.join(@tmp, 'work')
    FileUtils.mkdir_p @work
    ok, out = Vibe.run('git', 'init', '-q', '-b', 'main', chdir: @work)
    raise out unless ok
    Vibe.run('git', 'config', 'user.name', 'spec', chdir: @work)
    Vibe.run('git', 'config', 'user.email', 's@example.com', chdir: @work)
    File.write File.join(@work, 'README.md'), "hi\n"
    Vibe.run('git', 'add', '-A', chdir: @work)
    Vibe.run('git', 'commit', '-q', '-m', 'init', chdir: @work)
    ENV['VIBE_ROOT'] = @work
  end

  after do
    ENV.delete 'VIBE_ROOT'
    FileUtils.rm_rf @tmp
  end

  it 'serves the page with the app url and model' do
    res = req.get('/')
    expect(res.status).to eq 200
    expect(res.body).to include('<vibe-app').and include(Vibe.model)
  end

  it 'answers health as json' do
    res = req.get('/api/health')
    expect(res.status).to eq 200
    data = JSON.parse(res.body)
    expect(data['branch']).to eq 'main'
    expect(data['target']).to eq 'vibe'
    expect(data).to have_key('opencode')
  end

  it 'reports git status and diff' do
    File.write File.join(@work, 'README.md'), "hi\nthere\n"
    res = req.get('/api/git/status')
    expect(res.status).to eq 200
    expect(JSON.parse(res.body)['dirty'].map { |d| d['path'] }).to eq ['README.md']

    res = req.get('/api/git/diff?path=README.md')
    expect(res.body).to include('+there')
  end

  it 'commits through the api on the vibe branch' do
    Vibe::Git.ensure_branch!   # what `lux docker:vibe:run` does before the harness starts
    File.write File.join(@work, 'a.txt'), "a\n"
    res = json_post('/api/git/commit', message: 'add a')
    expect(res.status).to eq(200), res.body
    expect(JSON.parse(res.body)['files']).to eq ['a.txt']
    _, out = Vibe.run('git', 'rev-parse', '--abbrev-ref', 'HEAD', chdir: @work)
    expect(out.strip).to eq 'vibe'
  end

  it 'turns Vibe::Error into a 422 json' do
    res = req.post('/api/git/reset')
    expect(res.status).to eq 422
    expect(JSON.parse(res.body)['error']).to match(/clean/)
  end

  it 'proxies /oc/* to opencode with the directory pin' do
    with_upstream do |seen|
      res = json_post('/oc/session', title: 'x')
      expect(res.status).to eq(200), res.body
      expect(JSON.parse(res.body)).to eq('ok' => true)
      expect(seen[:line]).to start_with('POST /session?')
      expect(seen[:line]).to include("directory=#{Rack::Utils.escape(@work)}")
      expect(seen[:body]).to eq '{"title":"x"}'
    end
  end

  it 'answers 502 json when opencode is down' do
    ENV['VIBE_OC_URL'] = 'http://127.0.0.1:1'
    res = req.get('/oc/session')
    expect(res.status).to eq 502
    expect(JSON.parse(res.body)['error']).to match(/not reachable/)
  ensure
    ENV.delete 'VIBE_OC_URL'
  end
end
