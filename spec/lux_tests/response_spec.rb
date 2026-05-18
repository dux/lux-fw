require 'spec_helper'

describe Lux::Response do
  before do
    Lux::Current.new('http://test.example.com/')
  end

  let(:response) { Lux.current.response }

  describe 'Lux::UNSET' do
    it 'is defined and frozen' do
      expect(Lux::UNSET).to be_frozen
    end

    it 'inspects as "Lux::UNSET"' do
      expect(Lux::UNSET.inspect).to eq('Lux::UNSET')
    end
  end

  describe '#cache' do
    it 'returns a CachePolicy' do
      expect(response.cache).to be_a(Lux::Response::CachePolicy)
    end

    it 'defaults to private, max_age=0, no_store=false' do
      expect(response.cache.public?).to be false
      expect(response.cache.private?).to be true
      expect(response.cache.max_age).to eq(0)
      expect(response.cache.no_store?).to be false
    end

    it 'emits private must-revalidate by default' do
      expect(response.cache.header_value).to eq('private, must-revalidate, max-age=0')
    end

    it 'emits public when public=true' do
      response.cache.public  = true
      response.cache.max_age = 60
      expect(response.cache.header_value).to eq('public, max-age=60')
    end

    it 'emits no-store when no_store=true' do
      response.cache.no_store = true
      expect(response.cache.header_value).to eq('no-store')
    end

    it 'allow_cookies? only on private without no_store' do
      expect(response.cache.allow_cookies?).to be true

      response.cache.public = true
      expect(response.cache.allow_cookies?).to be false

      response.cache.public   = false
      response.cache.no_store = true
      expect(response.cache.allow_cookies?).to be false
    end
  end

  describe '#cache_public' do
    it 'sets public cache for given seconds' do
      response.cache_public 120
      expect(response.cache.public?).to be true
      expect(response.cache.max_age).to eq(120)
    end
  end

  describe '#no_store' do
    it 'enables no_store on cache' do
      response.no_store
      expect(response.cache.no_store?).to be true
      expect(response.cache.allow_cookies?).to be false
    end
  end

  describe '#max_age= (back-compat)' do
    it 'implies public cache when > 0' do
      response.max_age = 30
      expect(response.cache.public?).to be true
      expect(response.cache.max_age).to eq(30)
    end

    it 'cached? mirrors max_age > 0' do
      expect(response.cached?).to be false
      response.max_age = 5
      expect(response.cached?).to be true
    end
  end

  describe '#public= and #public?' do
    it 'delegate to cache policy' do
      response.public = true
      expect(response.public?).to be true
      expect(response.cache.public?).to be true
    end
  end

  describe '#body and #body=' do
    it 'reads nil when not set' do
      expect(response.body).to be_nil
    end

    it 'is set with body=' do
      response.body = 'hello'
      expect(response.body).to eq('hello')
    end

    it 'first set wins (back-compat)' do
      response.body = 'first'
      response.body = 'second'
      expect(response.body).to eq('first')
    end

    it 'block form transforms existing body' do
      response.body = 'foo'
      response.body { |b| b.upcase }
      expect(response.body).to eq('FOO')
    end

    it 'accepts opts hash for status side-effect' do
      response.body 'oops', status: 422
      expect(response.body).to eq('oops')
      expect(response.status).to eq(422)
    end
  end

  describe '#status' do
    it 'returns nil when unset' do
      expect(response.status).to be_nil
    end

    it 'is set via status=' do
      response.status = 404
      expect(response.status).to eq(404)
    end

    it 'is set via positional call' do
      response.status 201
      expect(response.status).to eq(201)
    end

    it 'falls back to 400 for non-numeric input' do
      response.status = 'oops'
      expect(response.status).to eq(400)
    end
  end

  describe '#content_type' do
    it 'returns nil when unset' do
      expect(response.content_type).to be_nil
    end

    it 'sets via setter and overrides on subsequent set' do
      response.content_type = :json
      expect(response.content_type).to eq('application/json')

      response.content_type = :html
      expect(response.content_type).to eq('text/html')
    end

    it 'maps :javascript to js mime' do
      response.content_type = :javascript
      expect(response.content_type).to eq(::Rack::Mime.mime_type('.js'))
    end
  end

  describe '#header' do
    it 'sets a single header' do
      response.header 'x-test', 'val'
      expect(response.headers['x-test']).to eq('val')
    end

    it 'sets multiple headers from a hash' do
      response.header({ 'x-a' => '1', 'x-b' => '2' })
      expect(response.headers['x-a']).to eq('1')
      expect(response.headers['x-b']).to eq('2')
    end
  end

  describe '#early_hints' do
    it 'stores hint pair' do
      response.early_hints '/a.css', 'style'
      response.early_hints '/a.css', 'style'   # duplicate ignored
      response.early_hints '/b.js', 'script'
      expect(response.early_hints.length).to eq(2)
    end

    it 'distinguishes same link with different type' do
      response.early_hints '/a.css', 'style'
      response.early_hints '/a.css', 'preload'
      expect(response.early_hints.length).to eq(2)
    end
  end
end

describe Lux::Response::CachePolicy do
  let(:response) { Lux::Response.new }
  let(:policy)   { response.cache }

  it 'stale_while_revalidate appears in header' do
    policy.public                 = true
    policy.max_age                = 30
    policy.stale_while_revalidate = 60
    expect(policy.header_value).to include('stale-while-revalidate=60')
  end

  it 'cached? is true when max_age > 0' do
    policy.max_age = 1
    expect(policy.cached?).to be true
  end
end
