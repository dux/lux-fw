require 'test_helper'

# Boot-level config that Lux.boot! would normally set; required because this
# spec drives the full Lux.render request pipeline.
%i(serve_static_files asset_root csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []
Lux.config[:logger_path_mask]     ||= './log/%s.log'
Lux.config[:logger_files_to_keep] ||= 3
Lux.config[:logger_file_max_size] ||= 10_240_000
Lux.config[:logger_formatter]     ||= nil

Lux::Plugin.load File.expand_path('..', __dir__)

class LocalizedTestController < Lux::Controller
  def root;  render text: 'public'; end
  def users; render text: 'users';  end
  def admin; render text: 'admin';  end
end

Lux.app do
  before { Lux.locale.detect }

  # response already written without a dispatch - localized must not touch it
  map 'ping' do
    lux.response.body 'pong'
  end

  # non-localized scope first: its dispatch ends routing for /admin
  map 'admin' do
    localized(false) do
      map 'users', 'localized_test#admin'
    end
    root 'localized_test#admin'
  end

  # optional: non-default prefixes pass, the default prefix is canonicalised away
  map 'users' do
    localized do
      root 'localized_test#users'
    end
  end

  # localized but opted out of the first-visit geo redirect
  map 'plain' do
    localized geo: false do
      root 'localized_test#users'
    end
  end

  # forced: the prefix is required, default locale included
  localized force: true do
    root 'localized_test#root'
  end
end

describe 'Lux::Application#localized' do
  before do
    Lux.locale.default         = :en
    Lux.locale.available       = %i[en de]
    Lux.current.locale         = nil
    Lux.current[:locale_force] = nil
  end

  it 'passes a prefix-less localized URL through' do
    resp = Lux.render.get('/users')
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'users'
  end

  it 'passes a non-default prefix through' do
    resp = Lux.render.get('/de/users')
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'users'
  end

  it 'strips the default locale prefix when not forced' do
    resp = Lux.render.get('/en/users')
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/users}
  end

  it 'redirects a prefix-less forced URL to the current locale' do
    resp = Lux.render.get('/', session: { locale: 'de' })
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/de}
  end

  it 'passes a prefixed forced URL through' do
    resp = Lux.render.get('/en')
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'public'
  end

  it 'strips the prefix from a non-localized URL' do
    resp = Lux.render.get('/de/admin')
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/admin}
  end

  it 'passes a prefix-less non-localized URL through' do
    resp = Lux.render.get('/admin')
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'admin'
  end

  it 'leaves a response already written by an earlier route alone' do
    resp = Lux.render.get('/ping')
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'pong'
  end
end

describe 'Lux::Locale#path' do
  before do
    Lux.locale.default         = :en
    Lux.locale.available       = %i[en de]
    Lux.current.locale         = nil
    Lux.current[:locale_force] = nil
  end

  it 'leaves the default locale bare' do
    _(Lux.locale.path('/service')).must_equal '/service'
    _(Lux.locale.path('/')).must_equal '/'
  end

  it 'prefixes a non-default locale' do
    _(Lux.locale.path('/service', locale: :de)).must_equal '/de/service'
    _(Lux.locale.path('/', locale: :de)).must_equal '/de'
  end

  it 'prefixes the default locale when the request is forced' do
    Lux.current[:locale_force] = true
    _(Lux.locale.path('/service')).must_equal '/en/service'
  end

  it 'uses the current locale' do
    Lux.current.locale = 'de'
    _(Lux.locale.path('/service')).must_equal '/de/service'
  end

  it 'localizes an object that responds to path' do
    Lux.current.locale = 'de'
    object = Struct.new(:path).new('/users/1')
    _(Lux.locale.path(object)).must_equal '/de/users/1'
  end

  it 'falls back to to_path' do
    Lux.current.locale = 'de'
    object = Struct.new(:to_path).new('/users/2')
    _(Lux.locale.path(object)).must_equal '/de/users/2'
  end

  it 'falls back to to_s' do
    _(Lux.locale.path(:service)).must_equal 'service'
  end

  it 'treats nil as the root' do
    _(Lux.locale.path(nil)).must_equal '/'
    _(Lux.locale.path(nil, locale: :de)).must_equal '/de'
  end
end

describe 'Lux::Locale#seo_links' do
  before do
    Lux.locale.default         = :en
    Lux.locale.available       = %i[en de]
    Lux.current.locale         = 'de'
    Lux.current[:locale_force] = nil
  end

  it 'canonicalizes the current locale, alternates every locale, then x-default' do
    links = Lux.locale.seo_links('/docs', base: 'https://example.com')

    _(links).must_equal [
      { rel: 'canonical', href: 'https://example.com/de/docs' },
      { rel: 'alternate', hreflang: 'en', href: 'https://example.com/docs' },
      { rel: 'alternate', hreflang: 'de', href: 'https://example.com/de/docs' },
      { rel: 'alternate', hreflang: 'x-default', href: 'https://example.com/docs' }
    ]
  end

  it 'ignores a trailing slash on the base' do
    links = Lux.locale.seo_links('/', base: 'https://example.com/')
    _(links.first[:href]).must_equal 'https://example.com/de'
  end
end

describe 'lpath delegates' do
  before do
    Lux.locale.default         = :en
    Lux.locale.available       = %i[en de]
    Lux.current.locale         = nil
    Lux.current[:locale_force] = nil
  end

  it 'is reachable as lux.lpath' do
    Lux.current.locale = 'de'
    _(Lux.current.lpath('/service')).must_equal '/de/service'
  end

  it 'is reachable as the lpath template helper' do
    Lux.current.locale = 'de'
    helper = Object.new.extend(Lux::Template::Helper)
    _(helper.lpath('/service')).must_equal '/de/service'
  end
end

describe 'Lux::Locale#geo_locale' do
  before do
    Lux.locale.default   = :en
    Lux.locale.available = %i[en hr de]
  end

  it 'maps a geo country to an available locale' do
    _(Lux.locale.geo_locale('HR')).must_equal :hr
    _(Lux.locale.geo_locale('de')).must_equal :de
  end

  it 'returns nil for unknown or unmapped countries' do
    _(Lux.locale.geo_locale('XX')).must_be_nil
    _(Lux.locale.geo_locale('US')).must_be_nil
    _(Lux.locale.geo_locale('')).must_be_nil
  end
end

describe 'localized first-visit geo redirect' do
  before do
    Lux.locale.default         = :en
    Lux.locale.available       = %i[en de]
    Lux.current.locale         = nil
    Lux.current[:locale_force] = nil
  end

  it 'sends a first-time visitor to their country locale' do
    resp = Lux.render.get('/users', headers: { 'CF-IPCountry' => 'DE' })
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/de/users}
  end

  it 'keeps the query string on the redirect' do
    resp = Lux.render.get('/users?x=1', headers: { 'CF-IPCountry' => 'DE' })
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/de/users\?.*x=1}
  end

  it 'uses geo on a forced scope too' do
    resp = Lux.render.get('/', headers: { 'CF-IPCountry' => 'DE' })
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/de(\?|\z)}
  end

  it 'leaves an unmapped-country visitor on the bare path' do
    resp = Lux.render.get('/users', headers: { 'CF-IPCountry' => 'US' })
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'users'
  end

  it 'does not redirect once a locale is remembered' do
    resp = Lux.render.get('/users', headers: { 'CF-IPCountry' => 'DE' }, session: { locale: 'en' })
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'users'
  end

  it 'a scope can opt out with geo: false' do
    resp = Lux.render.get('/plain', headers: { 'CF-IPCountry' => 'DE' })
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'users'
  end
end
