require 'test_helper'
require_relative '../load/authcog_router'
require_relative '../load/user_session'

describe AuthcogRouter do
  def with_host host
    was = Lux.config[:host]
    Lux.config[:host] = host
    yield
  ensure
    Lux.config[:host] = was
  end

  def base_for url
    AuthcogRouter.exchange_base(Lux::Utils::Url.new(url))
  end

  # what a view renders: a plain local path, so a link drawn into a shared layout
  # or a cached page carries no per-browser secret
  it 'links to its own mount path' do
    _(AuthcogRouter.auth_link).must_equal '/authcog'
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

  # the server-side exchange uses the same guarded host as the hand-off
  it 'exchanges a callback for the configured host when the request host is foreign' do
    with_host 'https://izlazni.com' do
      Lux::Context.new('https://evil.com/authcog')
      seen = nil
      Authcog.singleton_class.alias_method :__exchange, :exchange
      Authcog.define_singleton_method(:exchange) { |_hash, host:, port: nil| seen = host; { email: 'a@b.c' } }
      AuthcogRouter.allocate.send(:fetch_identity, 'a' * 40)
      _(seen).must_equal 'izlazni.com'
    ensure
      Authcog.singleton_class.alias_method :exchange, :__exchange
      Authcog.singleton_class.send(:remove_method, :__exchange)
    end
  end
end

describe 'Authcog.relying_url with authcog_hosts' do
  def relying url, hosts
    Authcog.relying_url(url, 'https://app.herokuapp.com', hosts: hosts).host
  end

  # a shared suffix: without the allowlist any *.herokuapp.com is "same domain"
  it 'trusts a sibling on a shared suffix without the allowlist' do
    _(relying('https://evil.herokuapp.com/authcog', nil)).must_equal 'evil.herokuapp.com'
  end

  it 'trusts only listed hosts when the allowlist is set' do
    hosts = %w[app.herokuapp.com www.example.com]
    _(relying('https://evil.herokuapp.com/authcog', hosts)).must_equal 'app.herokuapp.com'
    _(relying('https://WWW.example.com/authcog', hosts)).must_equal 'www.example.com'
  end
end

describe 'UserSession.local_path' do
  it 'keeps site-local paths' do
    _(UserSession.local_path('/')).must_equal '/'
    _(UserSession.local_path('/boards/x?tab=1')).must_equal '/boards/x?tab=1'
  end

  it 'drops anything that leaves the site' do
    [nil, '', 'https://evil.com', '//evil.com/x', '/\\evil.com', "/\t/evil.com", "/x\n", 'javascript:alert(1)'].each do |path|
      _(UserSession.local_path(path)).must_be_nil
    end
  end
end

describe 'UserSession.login_link' do
  before do
    @user_class = Object.const_get(:User) if Object.const_defined?(:User)
    Object.send(:remove_const, :User) if @user_class
    Object.const_set :User, Class.new {
      class << self
        attr_accessor :current
        def take(ref) = Struct.new(:ref, :email).new(ref, 'a@b.c')
      end
    }
  end

  after do
    Object.send(:remove_const, :User)
    Object.const_set(:User, @user_class) if @user_class
  end

  def follow link
    Lux::Context.new "http://test#{link}"
    catch(:done) { UserSession.resolve }
    Lux.ctx.session[UserSession::USER_REF]
  end

  it 'signs in once and refuses the same link again' do
    link = UserSession.login_link('u-ref-1')
    _(follow(link)).must_equal 'u-ref-1'
    _(follow(link)).must_be_nil
  end
end
