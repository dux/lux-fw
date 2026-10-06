# Vibe::Server routes through Rack::MockRequest: page, health, git api on a tmp
# repo, origin protection, and the /oc proxy against a stub upstream (plain
# TCPServer, no extra gems). Needs sinatra; skipped when it is not installed.
#
#   cd ~/dev/libs/lux-fw && bundle exec ruby -Ilib -Ispec plugins/vibe/spec/vibe_server_spec.rb

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'socket'
require 'rack/mock'

begin
  require_relative '../lib/vibe/server'
rescue LoadError => e
  describe 'Vibe::Server' do
    it 'needs sinatra' do
      skip "vibe server spec skipped: #{e.message}"
    end
  end
  return
end

describe Vibe::Server do
  def req
    Rack::MockRequest.new(Vibe::Server)
  end

  def json_post path, body, env = {}
    req.post(path, { input: JSON.generate(body), 'CONTENT_TYPE' => 'application/json' }.merge(env))
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

    # ensure_branch! writes safe.directory to the global config; keep that off ~/.gitconfig
    @env = ENV.to_h.slice('VIBE_ROOT', 'GIT_CONFIG_GLOBAL')
    ENV['GIT_CONFIG_GLOBAL'] = File.join(@tmp, 'gitconfig')
    File.write ENV['GIT_CONFIG_GLOBAL'], ''

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
    %w[VIBE_ROOT GIT_CONFIG_GLOBAL].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
    FileUtils.rm_rf @tmp
  end

  it 'serves the page with the app url and model' do
    res = req.get('/')
    assert_equal 200, res.status
    assert_includes res.body, '<vibe-app'
    assert_includes res.body, Vibe.model
  end

  it 'answers health as json' do
    res = req.get('/api/health')
    assert_equal 200, res.status
    data = JSON.parse(res.body)
    assert_equal 'main', data['branch']
    assert_equal 'vibe', data['target']
    assert_includes data.keys, 'opencode'
  end

  it 'reports git status and diff' do
    File.write File.join(@work, 'README.md'), "hi\nthere\n"
    res = req.get('/api/git/status')
    assert_equal 200, res.status
    assert_equal ['README.md'], JSON.parse(res.body)['dirty'].map { |d| d['path'] }

    res = req.get('/api/git/diff?path=README.md')
    assert_includes res.body, '+there'
  end

  it 'refuses a diff outside the repo with a 422' do
    res = req.get('/api/git/diff?path=/etc/passwd')
    assert_equal 422, res.status
    assert_match(/outside the repo/, JSON.parse(res.body)['error'])
  end

  it 'commits through the api on the vibe branch' do
    Vibe::Git.ensure_branch!   # what `lux docker:vibe:run` does before the harness starts
    File.write File.join(@work, 'a.txt'), "a\n"
    res = json_post('/api/git/commit', message: 'add a')
    assert_equal 200, res.status, res.body
    assert_equal ['a.txt'], JSON.parse(res.body)['files']
    _, out = Vibe.run('git', 'rev-parse', '--abbrev-ref', 'HEAD', chdir: @work)
    assert_equal 'vibe', out.strip
  end

  it 'turns Vibe::Error into a 422 json' do
    res = req.post('/api/git/reset')
    assert_equal 422, res.status
    assert_match(/clean/, JSON.parse(res.body)['error'])
  end

  describe 'origin protection' do
    before do
      Vibe::Git.ensure_branch!
      File.write File.join(@work, 'a.txt'), "a\n"
    end

    it 'rejects a write from a foreign origin' do
      res = json_post('/api/git/commit', { message: 'add a' }, 'HTTP_ORIGIN' => 'http://evil.example')
      assert_equal 403, res.status
      res = req.post('/api/git/reset', 'HTTP_ORIGIN' => 'http://evil.example')
      assert_equal 403, res.status
      assert File.exist?(File.join(@work, 'a.txt'))
      _, out = Vibe.run('git', 'log', '--format=%s', chdir: @work)
      assert_equal ['init'], out.lines.map(&:strip)
    end

    it 'accepts a write from the same origin' do
      # Rack::MockRequest serves from http://example.org
      res = json_post('/api/git/commit', { message: 'add a' }, 'HTTP_ORIGIN' => 'http://example.org')
      assert_equal 200, res.status, res.body
      assert_equal ['a.txt'], JSON.parse(res.body)['files']
    end
  end

  it 'proxies /oc/* to opencode with the directory pin' do
    with_upstream do |seen|
      res = json_post('/oc/session', title: 'x')
      assert_equal 200, res.status, res.body
      assert_equal({ 'ok' => true }, JSON.parse(res.body))
      assert seen[:line].start_with?('POST /session?'), seen[:line]
      assert_includes seen[:line], "directory=#{Rack::Utils.escape(@work)}"
      assert_equal '{"title":"x"}', seen[:body]
    end
  end

  it 'answers 502 json when opencode is down' do
    ENV['VIBE_OC_URL'] = 'http://127.0.0.1:1'
    res = req.get('/oc/session')
    assert_equal 502, res.status
    assert_match(/not reachable/, JSON.parse(res.body)['error'])
  ensure
    ENV.delete 'VIBE_OC_URL'
  end
end
