require 'test_helper'

describe Lux::Response do
  before do
    Lux::Current.new('http://test.example.com/')
  end

  def response
    @response ||= Lux.current.response
  end

  describe 'Lux::UNSET' do
    it 'is defined and frozen' do
      _(Lux::UNSET.frozen?).must_equal true
    end

    it 'inspects as "Lux::UNSET"' do
      _(Lux::UNSET.inspect).must_equal 'Lux::UNSET'
    end
  end

  describe '#cache' do
    it 'returns a CachePolicy' do
      _(response.cache).must_be_kind_of Lux::Response::CachePolicy
    end

    it 'defaults to private, max_age=0, no_store=false' do
      _(response.cache.public?).must_equal false
      _(response.cache.private?).must_equal true
      _(response.cache.max_age).must_equal 0
      _(response.cache.no_store?).must_equal false
    end

    it 'emits private must-revalidate by default' do
      _(response.cache.header_value).must_equal 'private, must-revalidate, max-age=0'
    end

    it 'emits public when public=true' do
      response.cache.public  = true
      response.cache.max_age = 60
      _(response.cache.header_value).must_equal 'public, max-age=60'
    end

    it 'emits no-store when no_store=true' do
      response.cache.no_store = true
      _(response.cache.header_value).must_equal 'no-store'
    end

    it 'allow_cookies? only on private without no_store' do
      _(response.cache.allow_cookies?).must_equal true

      response.cache.public = true
      _(response.cache.allow_cookies?).must_equal false

      response.cache.public   = false
      response.cache.no_store = true
      _(response.cache.allow_cookies?).must_equal false
    end
  end

  describe '#cache_public' do
    it 'sets public cache for given seconds' do
      response.cache_public 120
      _(response.cache.public?).must_equal true
      _(response.cache.max_age).must_equal 120
    end
  end

  describe '#no_store' do
    it 'enables no_store on cache' do
      response.no_store
      _(response.cache.no_store?).must_equal true
      _(response.cache.allow_cookies?).must_equal false
    end
  end

  describe '#max_age= (back-compat)' do
    it 'implies public cache when > 0' do
      response.max_age = 30
      _(response.cache.public?).must_equal true
      _(response.cache.max_age).must_equal 30
    end

    it 'cached? mirrors max_age > 0' do
      _(response.cached?).must_equal false
      response.max_age = 5
      _(response.cached?).must_equal true
    end
  end

  describe '#public= and #public?' do
    it 'delegate to cache policy' do
      response.public = true
      _(response.public?).must_equal true
      _(response.cache.public?).must_equal true
    end
  end

  describe '#body and #body=' do
    it 'reads nil when not set' do
      _(response.body).must_be_nil
    end

    it 'is set with body=' do
      response.body = 'hello'
      _(response.body).must_equal 'hello'
    end

    it 'first set wins (back-compat)' do
      response.body = 'first'
      response.body = 'second'
      _(response.body).must_equal 'first'
    end

    it 'block form transforms existing body' do
      response.body = 'foo'
      response.body { |b| b.upcase }
      _(response.body).must_equal 'FOO'
    end

    it 'accepts opts hash for status side-effect' do
      response.body 'oops', status: 422
      _(response.body).must_equal 'oops'
      _(response.status).must_equal 422
    end
  end

  describe '#status' do
    it 'returns nil when unset' do
      _(response.status).must_be_nil
    end

    it 'is set via status=' do
      response.status = 404
      _(response.status).must_equal 404
    end

    it 'is set via positional call' do
      response.status 201
      _(response.status).must_equal 201
    end

    it 'falls back to 400 for non-numeric input' do
      response.status = 'oops'
      _(response.status).must_equal 400
    end
  end

  describe '#content_type' do
    it 'returns nil when unset' do
      _(response.content_type).must_be_nil
    end

    it 'sets via setter and overrides on subsequent set' do
      response.content_type = :json
      _(response.content_type).must_equal 'application/json'

      response.content_type = :html
      _(response.content_type).must_equal 'text/html'
    end

    it 'maps :javascript to js mime' do
      response.content_type = :javascript
      _(response.content_type).must_equal ::Rack::Mime.mime_type('.js')
    end
  end

  describe '#header' do
    it 'sets a single header' do
      response.header 'x-test', 'val'
      _(response.headers['x-test']).must_equal 'val'
    end

    it 'sets multiple headers from a hash' do
      response.header({ 'x-a' => '1', 'x-b' => '2' })
      _(response.headers['x-a']).must_equal '1'
      _(response.headers['x-b']).must_equal '2'
    end
  end

  describe '#early_hints' do
    it 'stores hint pair' do
      response.early_hints '/a.css', 'style'
      response.early_hints '/a.css', 'style'   # duplicate ignored
      response.early_hints '/b.js', 'script'
      _(response.early_hints.length).must_equal 2
    end

    it 'distinguishes same link with different type' do
      response.early_hints '/a.css', 'style'
      response.early_hints '/a.css', 'preload'
      _(response.early_hints.length).must_equal 2
    end
  end
end

describe Lux::Response::CachePolicy do
  def response
    @response ||= Lux::Response.new
  end

  def policy
    @policy ||= response.cache
  end

  it 'stale_while_revalidate appears in header' do
    policy.public                 = true
    policy.max_age                = 30
    policy.stale_while_revalidate = 60
    _(policy.header_value).must_include 'stale-while-revalidate=60'
  end

  it 'cached? is true when max_age > 0' do
    policy.max_age = 1
    _(policy.cached?).must_equal true
  end
end
