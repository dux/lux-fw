require 'test_helper'

# Config defaults that Lux.boot! would normally set, needed because this spec
# walks the full request pipeline through Lux.render.
%i(serve_static_files asset_root csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []

class RequestTestRouter < Lux::Router
  allow :get, :post
  def echo
    render json: Lux.ctx.params.to_h
  end

  def go
    redirect_to '/request_test/echo'
  end

  def remember
    Lux.ctx.session[:seen] = Lux.ctx.params[:v]
    render text: 'ok'
  end

  def recall
    render text: Lux.ctx.session[:seen].to_s
  end

  def set_cookie
    Lux.ctx.session[:seen] = 1
    response.cookie 'theme', 'dark', max_age: 3600
    response.cookie 'old', nil
    render text: 'ok'
  end

  def flavor
    render text: "#{@flavor}:#{Lux.ctx.params[:x]}"
  end

  def cached
    return if etag('v1', last_modified: Time.utc(2026, 1, 1))
    render text: 'fresh body'
  end
end

class FilterHaltRouter < Lux::Router
  before { redirect_to '/login' if Lux.ctx.params[:login] }
  before { render text: 'denied', status: 403 if Lux.ctx.params[:deny] }
  before { redirect_to '/elsewhere' if Lux.ctx.params[:deny] }

  def show
    render text: 'shown'
  end
end

class HaltProbeRouter < Lux::Router
  before { Lux.ctx.response.header 'x-probe', '1' }

  def index
    render text: 'probe'
  end
end

Lux.router do
  before { Lux.ctx.response.body 'from before' if Lux.ctx.request.path == '/static_guard.txt' }
  before { Lux.ctx.response.body 'first' if Lux.ctx.request.path == '/halt_before' }
  before { Lux.ctx.response.header 'x-second', '1' if Lux.ctx.request.path == '/halt_before' }
  before { CSRF_PROBE_RAN << Lux.ctx.request.path if Lux.ctx.params[:csrf_probe] }
end

CSRF_PROBE_RAN ||= []

REQUEST_SPEC_ROUTE ||= proc do
  map 'request_test', 'request_test'
  map 'filter_halt', 'filter_halt#show'
  map '/request_flavor/:x', 'request_test#flavor', flavor: 'mint'

  map 'halt_body' do
    render text: 'stop'
    raise 'unreachable'
  end

  map 'raw_then_map' do
    Lux.ctx.response.body 'raw'
    map 'halt_probe#index'
  end
end

describe 'request pipeline' do
  before { Lux.router.route(&REQUEST_SPEC_ROUTE) }

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

  describe 'Static files' do
    it 'leaves a path to the before hook that answered it' do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p File.join(dir, 'public')
        File.write File.join(dir, 'public/static_guard.txt'), 'from public'
        File.write File.join(dir, 'public/static_plain.txt'), 'plain file'
        was = Lux.config[:serve_static_files]
        Lux.config[:serve_static_files] = true

        Dir.chdir(dir) do
          # the body is set-once, so a leaked file shows up as its headers
          page = Lux.render.get('/static_guard.txt')
          assert_body_includes 'from before', page
          assert_nil page.headers['last-modified']
          assert_nil page.headers['access-control-allow-origin']

          assert_body_includes 'plain file', Lux.render.get('/static_plain.txt')
        end
      ensure
        Lux.config[:serve_static_files] = was
      end
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

    it 'answers a dot segment in the path with 400' do
      assert_status 400, Lux.render.get('/request_test/../config/config.yaml')
      assert_status 400, Lux.render.get('/request_test/%2e%2e/echo')
      assert_status 400, Lux.render.get('/./request_test/echo')
      assert_status 200, Lux.render.get('/request_test/echo?v=..')
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

  describe 'Router before filters' do
    it 'stops the chain once a filter wrote the response' do
      page = Lux.render.get('/filter_halt', params: { deny: 1 })

      assert_status 403, page
      assert_body_includes 'denied', page
    end

    it 'redirects from a before filter' do
      page = Lux.render.get('/filter_halt', params: { login: 1 })

      assert_status 302, page
      assert_equal '/login', URI.parse(page.redirect_to).path
    end

    it 'runs the action when no filter answers' do
      assert_body_includes 'shown', Lux.render.get('/filter_halt')
    end
  end

  describe 'CSRF' do
    it 'rejects a forged POST before any before filter runs' do
      previous = Lux.config[:csrf]
      Lux.config[:csrf] = true
      CSRF_PROBE_RAN.clear
      page = Lux.render.post('/request_test/echo', params: { csrf_probe: 1 }, headers: {
        'Authorization'  => 'Basic dTpw',
        'Sec-Fetch-Site' => 'cross-site',
      })

      assert_status 403, page
      _(CSRF_PROBE_RAN).must_equal []
    ensure
      Lux.config[:csrf] = previous
    end
  end

  describe 'Router halting' do
    it 'stops app before hooks once one wrote the body' do
      page = Lux.render.get('/halt_before')

      assert_equal 'first', page.body
      assert_nil page.headers['x-second']
    end

    it 'ends routing when a route sets the body' do
      page = Lux.render.get('/halt_body')

      assert_status 200, page
      assert_equal 'stop', page.body
    end

    it 'does not dispatch once the body is written' do
      page = Lux.render.get('/raw_then_map')

      assert_equal 'raw', page.body
      assert_nil page.headers['x-probe']
    end
  end

  describe 'Request hygiene' do
    it 'answers /healthcheck without routing' do
      page = Lux.render.get('/healthcheck')

      assert_status 200, page
      assert_equal 'ok', page.body
    end

    it 'rejects a bare IP host' do
      assert_status 403, Lux.render.get('http://127.0.0.1/')
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
      assert_equal 'RequestTestRouter#echo', line['dispatch']
    ensure
      Lux.config[:log_requests] = false
      Lux::LOGGER_CACHE.delete(:request)
    end

    it 'masks credential-looking params' do
      params = { 'email' => 'a@b.c', 'password' => 'x', 'user' => { 'api_token' => 'y' } }
      out    = Lux::Router.allocate.send(:filter_params, params)

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
end
