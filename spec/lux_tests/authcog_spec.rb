require 'test_helper'
require_relative '../../plugins/authcog/load/authcog_controller'
require_relative '../../plugins/authcog/load/user_session'

describe AuthcogController do
  def with_host host
    was = Lux.config[:host]
    Lux.config[:host] = host
    yield
  ensure
    Lux.config[:host] = was
  end

  def base_for url
    AuthcogController.exchange_base(Lux::Utils::Url.new(url))
  end

  # what a view renders: a plain local path, so a link drawn into a shared layout
  # or a cached page carries no per-browser secret
  it 'links to its own mount path' do
    _(AuthcogController.auth_link).must_equal '/authcog'
  end

  it 'builds the exchange base with the development port' do
    with_host 'http://lvh.me:3000' do
      _(base_for('http://lvh.me:3000/authcog')).must_equal 'https://auth.authcog.com/domain:lvh.me/port:3000'
    end
  end

  it 'builds the exchange base without a production default port' do
    with_host 'https://izlazni.com' do
      _(base_for('https://izlazni.com/authcog')).must_equal 'https://auth.authcog.com/domain:izlazni.com'
    end
  end

  it 'omits the default http port' do
    with_host 'http://lvh.me' do
      _(base_for('http://lvh.me:80/authcog')).must_equal 'https://auth.authcog.com/domain:lvh.me'
    end
  end

  it 'keeps a subdomain of the configured domain' do
    with_host 'https://izlazni.com' do
      _(base_for('https://app.izlazni.com/authcog')).must_equal 'https://auth.authcog.com/domain:app.izlazni.com'
    end
  end

  # a forged Host header must not pick the domain a stolen hash is exchanged for
  it 'falls back to the configured host for a foreign request host' do
    with_host 'https://izlazni.com' do
      _(base_for('https://evil.com/authcog')).must_equal 'https://auth.authcog.com/domain:izlazni.com'
    end
  end
end

describe 'UserSession.local_path' do
  it 'keeps site-local paths' do
    _(UserSession.local_path('/')).must_equal '/'
    _(UserSession.local_path('/boards/x?tab=1')).must_equal '/boards/x?tab=1'
  end

  it 'drops anything that leaves the site' do
    [nil, '', 'https://evil.com', '//evil.com/x', '/\\evil.com', 'javascript:alert(1)'].each do |path|
      _(UserSession.local_path(path)).must_be_nil
    end
  end
end
