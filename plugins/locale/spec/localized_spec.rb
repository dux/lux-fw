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

  localized force: true do
    root  'localized_test#root'
    map 'users', 'localized_test#users'
  end
end

describe 'Lux::Application#localized' do
  before do
    Lux.locale.default   = :en
    Lux.locale.available = %i[en de]
  end

  it 'redirects a prefix-less localized URL to the current locale' do
    resp = Lux.render.get('/users')
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/en/users}
  end

  it 'uses the session locale for the redirect target' do
    resp = Lux.render.get('/', session: { locale: 'de' })
    _(resp.status).must_equal 302
    _(resp.headers['location']).must_match %r{\A/de}
  end

  it 'passes a prefixed localized URL through' do
    resp = Lux.render.get('/de/users')
    _(resp.status).must_equal 200
    _(resp.body).must_equal 'users'
  end

  it 'strips the prefix from a non-localized URL' do
    resp = Lux.render.get('/en/admin')
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
