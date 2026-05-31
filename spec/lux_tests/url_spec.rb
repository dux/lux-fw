require 'test_helper'

# Tests for the vendored Lux::Utils::Url (formerly the lux-url gem).
# Covers the parser, mutators, and the new Lux.url / Lux.current.url
# entry points. Class methods that consult the current request use the
# Lux::Current shim already used by nav_spec.

describe Lux::Utils::Url do
  describe 'integration' do
    it 'is aliased as top-level Url for back-compat' do
      _(Url).must_equal Lux::Utils::Url
    end

    it 'Lux.url(str) builds a new instance' do
      u = Lux.url('https://lvh.me/foo?a=1')
      _(u).must_be_kind_of Lux::Utils::Url
      _(u.to_s).must_equal 'https://lvh.me/foo?a=1'
    end

    it 'Lux.url with no arg uses the current request URL' do
      Lux::Current.new('http://example.com/foo?bar=1')
      _(Lux.url.to_s).must_equal 'http://example.com/foo?bar=1'
    end

    it 'Lux.current.url returns a Url for the current request' do
      Lux::Current.new('http://example.com/x?y=2')
      u = Lux.current.url
      _(u).must_be_kind_of Lux::Utils::Url
      _(u[:y]).must_equal '2'
    end
  end

  describe 'parsing' do
    it 'parses basic absolute urls' do
      url_s = 'https://lvh.me/foo/bar?baz=123'
      url = Lux.url(url_s)
      _(url.port).must_be_nil
      _(url.path).must_equal '/foo/bar'
      _(url.qs('baz')).must_equal '123'
      _(url.to_s).must_equal url_s
    end

    it 'parses path prefix segments' do
      list = %w(foo baz)
      url_s = 'https://lvh.me/:%s/some-path?baz=123' % list.join(':')
      url = Lux.url(url_s)
      _(url.path_prefix).must_equal list
      _(url.to_s).must_equal url_s
    end

    it 'reads path-qs and querystring independently' do
      url = Lux.url('https://lvh.me/base/foo:bar/baz:1?baz=123&boo=456')
      _(url[:foo]).must_equal 'bar'        # falls back to path qs
      _(url[:baz]).must_equal '123'        # qs wins over path qs
      _(url[:boo]).must_equal '456'
      _(url.path_qs).must_equal({ 'baz' => '1', 'foo' => 'bar' })
      _(url.pqs(:baz)).must_equal '1'
      _(url.qs(:baz)).must_equal '123'
    end

    it 'detects co.uk-style two-letter TLD' do
      url = Lux.url('https://www.example.co.uk/')
      _(url.domain).must_equal 'example.co.uk'
      _(url.subdomain).must_equal 'www'
    end

    it 'pulls a 2-letter and hyphenated locale prefix' do
      _(Lux.url('/fr/foo').locale).must_equal 'fr'
      _(Lux.url('/en-UK/foo').locale).must_equal 'en-UK'
    end

    it 'strips default ports and keeps explicit ones' do
      _(Lux.url('http://lvh.me:80/').port).must_be_nil
      _(Lux.url('https://lvh.me:443/').port).must_be_nil
      _(Lux.url('https://lvh.me:3000/').port).must_equal '3000'
    end

    it 'parses a fragment after the query string' do
      url = Lux.url('https://lvh.me/path?a=1#section')
      _(url.to_s).must_include '#section'
    end
  end

  describe 'mutation' do
    it 'encodes qs on render' do
      url = Lux.url('/foo')
      url.qs[:foo] = 'a/b|c d'
      _(url.to_s).must_equal '/foo?foo=a%2Fb%7Cc+d'
    end

    it 'qs with explicit nil deletes the key' do
      url = Lux.url('/foo?a=1')
      url.qs(:a, nil)
      _(url.qs(:a)).must_be_nil
    end

    it 'delete removes multiple keys' do
      url = Lux.url('/foo?a=1&b=2&c=3').delete(:a, :b)
      _(url.qs).must_equal({ 'c' => '3' })
    end

    it 'pqs CGI-escapes values on write' do
      url = Lux.url('/foo')
      url.pqs(:name, 'a b')
      _(url.path).must_include 'name:a+b'
    end

    it 'renders path-qs without a double slash when there is no regular path' do
      url = Lux.url('http://auth.lvh.me:3000/domain:lvh.me/port:3000')
      url.pqs(:domain, "app.#{url.host}")
      url.pqs(:port, url.port)

      _(url.to_s).must_equal 'http://auth.lvh.me:3000/port:3000/domain:app.auth.lvh.me'
    end

    it 'hash sets the fragment and is chainable' do
      url = Lux.url('/foo')
      assert_same url, url.hash('section')
      _(url.to_s).must_equal '/foo#section'
    end

    it 'sorts qs keys alphabetically on render' do
      _(Lux.url('/x?z=1&a=2&m=3').to_s).must_equal '/x?a=2&m=3&z=1'
    end
  end

  describe 'class helpers against current request' do
    before do
      Lux::Current.new('https://base.lvh.me:3000/fr/some/path?foo=bar')
    end

    it 'Url.escape / Url.unescape round-trip' do
      _(Url.escape('a b/c')).must_equal 'a+b%2Fc'
      _(Url.unescape('a+b%2Fc')).must_equal 'a b/c'
    end

    it 'Url.escape returns "" for nil' do
      _(Url.escape(nil)).must_equal ''
    end

    it 'Url.qs replaces the querystring on the current url' do
      _(Url.qs(:foo, :baz)).must_equal '/fr/some/path?foo=baz'
      _(Url.qs(:bar, :baz)).must_equal '/fr/some/path?bar=baz&foo=bar'
    end

    it 'Url.pqs writes a path-qs segment and clears the matching qs' do
      _(Url.pqs(:foo, :baz)).must_equal '/fr/some/path/foo:baz'
    end

    it 'Url.locale swaps the locale prefix' do
      _(Url.locale(:en)).must_equal '/en/some/path?foo=bar'
    end

    it 'Url.subdomain rewrites the subdomain' do
      _(Url.subdomain('admin')).must_equal 'https://admin.lvh.me:3000/fr/some/path?foo=bar'
    end

    it 'Url.subdomain with nil drops to the apex/root' do
      _(Url.subdomain(nil)).must_equal 'https://lvh.me:3000/fr/some/path?foo=bar'
    end

    it 'Url.host returns host of the current request' do
      _(Url.host).must_equal 'base.lvh.me'
    end

    it 'Url.root returns proto + host + port' do
      _(Url.root).must_equal 'https://base.lvh.me:3000'
    end
  end

  describe 'output' do
    it 'to_h returns a structured snapshot' do
      h = Lux.url('https://a.b.lvh.me:3000/en/x?q=1#frag').to_h
      _(h[:proto]).must_equal 'https'
      _(h[:port]).must_equal '3000'
      _(h[:domain][:full]).must_equal 'a.b.lvh.me'
      _(h[:domain][:subdomain]).must_equal 'a.b'
      _(h[:locale]).must_equal 'en'
      _(h[:qs]).must_equal({ 'q' => '1' })
      _(h[:hash]).must_equal '#frag'
    end

    it 'to_s returns the relative form when no domain is present' do
      _(Lux.url('/x?a=1').to_s).must_equal '/x?a=1'
    end
  end
end
