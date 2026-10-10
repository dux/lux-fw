require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

require_relative '../load/lib/exception_writer'

describe ExceptionWriter do
  def log_file
    @root.join('log/app.exceptions.log')
  end

  def lines
    log_file.read.lines.map { |line| JSON.parse(line) }
  end

  before do
    @root = Pathname.new(Dir.mktmpdir('lux-exceptions-'))
    @prev_root = Lux.instance_variable_get(:@lux_app_root)
    Lux.instance_variable_set(:@lux_app_root, @root)
    Thread.current[:lux] = nil
  end

  after do
    Lux.instance_variable_set(:@lux_app_root, @prev_root)
    Thread.current[:lux] = nil
    FileUtils.remove_entry @root if @root.exist?
  end

  def error message = 'boom'
    err = RuntimeError.new(message)
    err.set_backtrace([
      '/gems/rack/lib/rack.rb:12:in `call\'',
      @root.join('app/models/thing.rb:42:in `run\'').to_s
    ])
    err
  end

  it 'appends one compact JSON line and creates the log directory' do
    refute log_file.exist?
    ExceptionWriter.new(error).write

    _(log_file.exist?).must_equal true
    _(lines.length).must_equal 1
    _(log_file.read.end_with?("\n")).must_equal true
  end

  it 'records the seven documented fields' do
    ExceptionWriter.new(error).write
    row = lines.first

    _(row.keys).must_equal %w[uid dump message ts]
    _(row['message']).must_equal 'boom'
    _(row['dump']).must_include 'boom (RuntimeError)'
    _(row['ts']).must_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/)
  end

  it 'fingerprints the first application frame as a path relative to Lux.root' do
    uid = Digest::SHA256.hexdigest(JSON.generate(['app/models/thing.rb', 42, 'RuntimeError']))

    ExceptionWriter.new(error).write
    _(lines.first['uid']).must_equal uid
  end

  it 'falls back to the first frame when no frame lives under Lux.root' do
    err = RuntimeError.new('boom')
    err.set_backtrace(['/gems/rack/lib/rack.rb:12:in `call\''])
    uid = Digest::SHA256.hexdigest(JSON.generate(['/gems/rack/lib/rack.rb', 12, 'RuntimeError']))

    ExceptionWriter.new(err).write
    _(lines.first['uid']).must_equal uid
  end

  it 'uses empty file and zero line without a backtrace' do
    err = RuntimeError.new('boom')
    err.set_backtrace(nil)
    uid = Digest::SHA256.hexdigest(JSON.generate(['', 0, 'RuntimeError']))

    ExceptionWriter.new(err).write
    _(lines.first['uid']).must_equal uid
  end

  it 'moves with the frame line and class but not the message' do
    first = Digest::SHA256.hexdigest(JSON.generate(['app/models/thing.rb', 42, 'RuntimeError']))
    ExceptionWriter.new(error('one')).write
    ExceptionWriter.new(error('two')).write
    _(lines.map { |l| l['uid'] }.uniq).must_equal [first]
  end

  it 'includes caller metadata and omits it by default' do
    ExceptionWriter.new(error).write(user: 'u_42', tags: %w[checkout], description: 'Confirming order', ip: '203.0.113.7')

    row = lines.first
    _(row['user']).must_equal 'u_42'
    _(row['tags']).must_equal %w[checkout]
    _(row['description']).must_equal 'Confirming order'
    _(row['ip']).must_equal '203.0.113.7'

    ExceptionWriter.new(error('plain')).write
    plain = lines.last
    _(plain.keys).must_equal %w[uid dump message ts]
  end

  it 'falls back to the request IP when ip is not given' do
    Lux::Current.new('http://test-writer')
    Lux.current.request.env['REMOTE_ADDR'] = '198.51.100.9'

    ExceptionWriter.new(error).write
    _(lines.first['ip']).must_equal '198.51.100.9'
  end

  it 'records the request method, url and allowlisted headers' do
    Lux::Current.new(Rack::MockRequest.env_for('http://test-writer/sites/1?tab=seo', method: 'POST',
      'HTTP_USER_AGENT' => 'Mozilla/5.0', 'HTTP_REFERER' => 'http://test-writer/sites',
      'HTTP_COOKIE' => 'sid=secret', 'HTTP_AUTHORIZATION' => 'Bearer secret'))

    ExceptionWriter.new(error).write
    row = lines.first
    _(row['method']).must_equal 'POST'
    _(row['url']).must_equal 'http://test-writer/sites/1?tab=seo'
    _(row['headers']).must_equal('User-Agent' => 'Mozilla/5.0', 'Referer' => 'http://test-writer/sites')
  end

  it 'masks credential query params in the url and referer' do
    Lux::Current.new(Rack::MockRequest.env_for('http://test-writer/x?sso_action=tok&tab=seo',
      'HTTP_REFERER' => 'http://test-writer/y?api_key=k1'))

    ExceptionWriter.new(error).write
    row = lines.first
    _(row['url']).must_equal 'http://test-writer/x?sso_action=[FILTERED]&tab=seo'
    _(row['headers']['Referer']).must_equal 'http://test-writer/y?api_key=[FILTERED]'
  end

  it 'falls back to the signed-in user email, caller user wins' do
    Lux::Current.new('http://test-writer')
    Lux.current.define_singleton_method(:user) { Struct.new(:email).new('ana@example.com') }

    ExceptionWriter.new(error).write
    ExceptionWriter.new(error).write(user: 'u_42')
    _(lines.map { |l| l['user'] }).must_equal ['ana@example.com', 'u_42']
  end

  it 'keeps concurrent writers from interleaving records' do
    error('one')
    pids = 8.times.map do
      fork do
        Thread.current[:lux] = nil
        ExceptionWriter.new(error('child')).write
        exit!(0)
      end
    end
    pids.each { |pid| Process.wait(pid) }

    rows = lines
    _(rows.length).must_equal 8
    _(rows.map { |r| r['message'] }.uniq).must_equal ['child']
  end
end
