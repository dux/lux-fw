# LuxJob::Server routes through Rack::MockRequest: the AuthCog gate, the
# admin-email allowlist and the dashboard. Needs sinatra; skipped when it is
# not installed.
#
#   cd ~/dev/libs/lux-fw && bundle exec ruby -Ilib -Ispec plugins/job_runner/spec/lux_job_server_spec.rb

require 'test_helper'
require_relative 'support/db'

begin
  require 'rack/mock'
  require_relative '../lib/lux_job_server'
rescue LoadError => e
  describe 'LuxJob::Server' do
    it 'needs sinatra' do
      skip "lux job server spec skipped: #{e.message}"
    end
  end
  return
end

describe LuxJob::Server do
  ADMIN ||= 'admin@example.com'

  def req
    Rack::MockRequest.new(LuxJob::Server)
  end

  # Log in through the real challenge flow: follow /authcog, pull the state off
  # the redirect and the session cookie, then hit the callback with both.
  # AuthCog.exchange is swapped for a canned identity (no network).
  def login(email)
    start = req.get('/authcog')
    state = Rack::Utils.parse_query(URI(start.headers['Location']).query)['state']
    cookie = start.headers['Set-Cookie'].to_s.split(';').first

    with_exchange(email) do
      req.get("/authcog?callback=#{'a' * 40}&state=#{state}", 'HTTP_COOKIE' => cookie)
    end
  end

  def with_exchange(email)
    original = Authcog.method(:exchange)
    Authcog.define_singleton_method(:exchange) { |_cb, **_kw| { email: email, provider: 'google' } }
    yield
  ensure
    Authcog.define_singleton_method(:exchange, original)
  end

  before do
    Lux.config.host = 'http://lvh.me:3000'
    Lux.config.admin_emails = [ADMIN]
    LuxJob::JOBS.clear
  end

  it 'redirects a guest to the authcog entry point' do
    res = req.get('/')

    _(res.status).must_equal 302
    assert_includes res.headers['Location'], '/authcog'
  end

  it 'sends the visitor to authcog with a challenge' do
    res = req.get('/authcog')

    _(res.status).must_equal 302
    location = res.headers['Location']
    assert_includes location, 'auth.authcog.com/domain:lvh.me/port:3000'
    assert Rack::Utils.parse_query(URI(location).query)['state']
  end

  it 'rejects an email outside admin_emails at the callback' do
    res = login('stranger@example.com')

    _(res.status).must_equal 403
    assert_includes res.body, 'Access denied'
  end

  it 'accepts an allowlisted email and opens the dashboard' do
    res = login(ADMIN)
    _(res.status).must_equal 302
    assert_includes res.headers['Location'], '/'

    cookie = res.headers['Set-Cookie'].to_s.split(';').first
    page = req.get('/', 'HTTP_COOKIE' => cookie)

    _(page.status).must_equal 200
    assert_includes page.body, 'LuxJob Dashboard'
  end

  it 'renders a pjax container and loads fez' do
    res = login(ADMIN)
    cookie = res.headers['Set-Cookie'].to_s.split(';').first
    page = req.get('/', 'HTTP_COOKIE' => cookie)

    assert_includes page.body, 'class="pjax"'
    assert_includes page.body, LuxJob::Server::FEZ_ONLINE
  end

  it 'returns 404 for /fez.js when no local fez build is installed' do
    _(req.get('/fez.js').status).must_equal 404
  end

  it 'renders a job page with the trigger form' do
    LuxJob.define(:sample_job) { 'ok' }
    res = login(ADMIN)
    cookie = res.headers['Set-Cookie'].to_s.split(';').first
    page = req.get('/jobs/sample_job', 'HTTP_COOKIE' => cookie)

    _(page.status).must_equal 200
    assert_includes page.body, 'Add Job'
    assert_includes page.body, 'data-job="sample_job"'
  end

  it 'fails closed when admin_emails is empty' do
    Lux.config.admin_emails = []
    res = login(ADMIN)

    _(res.status).must_equal 403
  end

  it 'gates the log api' do
    res = req.get('/api/log')

    _(res.status).must_equal 302
    assert_includes res.headers['Location'], '/authcog'
  end

  it 'shows a jobs subdomain url by default' do
    _(LuxJob::Server.display_url).must_match %r{\Ahttp://jobs\.lvh\.me:\d+\z}
  end

  it 'accepts a host outside the sinatra development allow-list' do
    res = req.get('/', 'HTTP_HOST' => 'jobs.lvh.me:3001')

    _(res.status).must_equal 302
    assert_includes res.headers['Location'], '/authcog'
  end

  it 'honours LUX_JOB_URL' do
    was = ENV['LUX_JOB_URL']
    ENV['LUX_JOB_URL'] = 'https://jobs.example.com'
    _(LuxJob::Server.display_url).must_equal 'https://jobs.example.com'
  ensure
    ENV['LUX_JOB_URL'] = was
  end
end
