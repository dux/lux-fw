require 'test_helper'

# Config defaults that Lux.boot! would normally set, needed because this spec
# walks the full request pipeline through Lux.render.
%i(serve_static_files asset_root csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []

class RequestTestController < Lux::Controller
  allow :get, :post
  def echo
    render json: lux.params.to_h
  end

  def go
    redirect_to '/request_test/echo'
  end

  def remember
    lux.session[:seen] = lux.params[:v]
    render text: 'ok'
  end

  def recall
    render text: lux.session[:seen].to_s
  end

  def set_cookie
    lux.session[:seen] = 1
    response.cookie 'theme', 'dark', max_age: 3600
    response.cookie 'old', nil
    render text: 'ok'
  end

  def flavor
    render text: "#{@flavor}:#{lux.params[:x]}"
  end

  def cached
    return if etag('v1', last_modified: Time.utc(2026, 1, 1))
    render text: 'fresh body'
  end
end

class FilterHaltController < Lux::Controller
  before { redirect_to '/login' if lux.params[:login] }
  before_action { render text: 'denied', status: 403 if lux.params[:deny] }
  before_action { redirect_to '/elsewhere' if lux.params[:deny] }
  after { lux.response.header 'x-after', 'ran' }

  def show
    render text: 'shown'
  end
end

Lux.app do
  map 'request_test', 'request_test'
  map 'filter_halt', 'filter_halt#show'
  map '/request_flavor/:x', 'request_test#flavor', flavor: 'mint'
end

describe 'Lux.render result' do
  it 'exposes status, raw body, parsed json and ok?' do
    page = Lux.render.get('/request_test/echo', params: { q: 'x' })

    assert_status 200, page
    assert page.ok?
    assert_kind_of String, page.body
    assert_json_includes({ q: 'x' }, page)
  end

  it 'reads the redirect target' do
    page = Lux.render.get('/request_test/go')

    assert_status 302, page
    refute page.ok?
    assert_match %r{\A/request_test/echo}, page.redirect_to
  end

  it 'carries the session between calls with a client' do
    client = Lux.render.client
    client.get('/request_test/remember', params: { v: 'kept' })

    assert_body_includes 'kept', client.get('/request_test/recall')
  end
end

describe 'Request id' do
  it 'generates one and echoes it' do
    page = Lux.render.get('/request_test/echo')

    assert_match(/\A\h{20}\z/, page.headers['x-request-id'])
  end

  it 'keeps a sane upstream id and replaces an unsafe one' do
    kept = Lux.render.get('/request_test/echo', headers: { 'X-Request-Id' => 'abc-123@edge' })
    replaced = Lux.render.get('/request_test/echo', headers: { 'X-Request-Id' => "bad id\n" })

    assert_equal 'abc-123@edge', kept.headers['x-request-id']
    assert_match(/\A\h{20}\z/, replaced.headers['x-request-id'])
  end
end

describe 'Malformed input' do
  it 'answers a broken query string with 400' do
    assert_status 400, Lux.render.get('/request_test/echo?a=%')
    assert_status 400, Lux.render.get('/request_test/echo?a[]=1&a[b]=2')
  end

  it 'answers a broken JSON body with 400' do
    page = Lux.render.post('/request_test/echo', body: '{"a":', headers: { 'Content-Type' => 'application/json' })

    assert_status 400, page
  end

  it 'merges a JSON object body into params' do
    page = Lux.render.post('/request_test/echo?q=1', body: '{"name":"Dux"}', headers: { 'Content-Type' => 'application/json' })

    assert_json_includes({ q: '1', name: 'Dux' }, page)
  end
end

describe 'Controller filters' do
  it 'stops the chain once a filter wrote the response' do
    page = Lux.render.get('/filter_halt', params: { deny: 1 })

    assert_status 403, page
    assert_body_includes 'denied', page
  end

  it 'runs after callbacks when a before filter redirects' do
    page = Lux.render.get('/filter_halt', params: { login: 1 })

    assert_status 302, page
    assert_equal 'ran', page.headers['x-after']
  end

  it 'runs the action when no filter answers' do
    assert_body_includes 'shown', Lux.render.get('/filter_halt')
  end
end

describe 'Request logging' do
  it 'writes one JSON line per request when log_requests is on' do
    buf = StringIO.new
    Lux::LOGGER_CACHE[:request] = Logger.new(buf)
    Lux.config[:log_requests] = true

    Lux.render.get('/request_test/echo?token=x', headers: { 'X-Request-Id' => 'log-1' })
    line = JSON.parse(buf.string.lines.last)

    assert_equal 'log-1', line['id']
    assert_equal 200, line['status']
    assert_equal '/request_test/echo', line['path']
    assert_equal 'RequestTestController#echo', line['dispatch']
  ensure
    Lux.config[:log_requests] = false
    Lux::LOGGER_CACHE.delete(:request)
  end

  it 'masks credential-looking params' do
    params = { 'email' => 'a@b.c', 'password' => 'x', 'user' => { 'api_token' => 'y' } }
    out    = Lux::Application.allocate.send(:filter_params, params)

    assert_equal({ 'email' => 'a@b.c', 'password' => '[FILTERED]', 'user' => { 'api_token' => '[FILTERED]' } }, out)
  end
end

describe 'Conditional GET' do
  def tag
    @tag ||= Lux.render.get('/request_test/cached').headers['etag']
  end

  it 'answers 304 for a weak/strong match anywhere in the If-None-Match list' do
    bare = tag.delete_prefix('W/')

    assert_status 304, Lux.render.get('/request_test/cached', headers: { 'If-None-Match' => %("other", #{bare}) })
    assert_status 304, Lux.render.get('/request_test/cached', headers: { 'If-None-Match' => '*' })
    assert_status 200, Lux.render.get('/request_test/cached', headers: { 'If-None-Match' => '"other"' })
  end

  it 'answers If-Modified-Since from last_modified' do
    page = Lux.render.get('/request_test/cached')
    assert_equal Time.utc(2026, 1, 1).httpdate, page.headers['last-modified']

    assert_status 304, Lux.render.get('/request_test/cached', headers: { 'If-Modified-Since' => Time.utc(2026, 2, 1).httpdate })
    assert_status 200, Lux.render.get('/request_test/cached', headers: { 'If-Modified-Since' => Time.utc(2025, 1, 1).httpdate })
  end

  it 'tags HEAD responses like GET' do
    head = Lux.render.head('/request_test/echo').headers['etag']

    refute_nil head
    assert_equal Lux.render.get('/request_test/echo').headers['etag'], head
  end
end

describe 'response.cookie' do
  it 'sends app cookies next to the session cookie' do
    cookies = Array(Lux.render.get('/request_test/set_cookie').headers['set-cookie'])

    assert_equal 3, cookies.length
    assert_includes cookies, 'theme=dark; path=/; max-age=3600; httponly; samesite=lax'
    assert cookies.any? { _1.start_with?('old=; ') && _1.include?('max-age=0') }
    assert cookies.any? { _1.start_with?(Lux.config[:session_cookie_name] || 'lux_') }
  end
end

describe 'map options' do
  it 'passes route options to an absolute-path target as ivars' do
    assert_body_includes 'mint:42', Lux.render.get('/request_flavor/42')
  end
end
