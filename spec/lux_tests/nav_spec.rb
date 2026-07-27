require 'test_helper'

describe Lux::Application::Nav do
  def nav_for path, host: 'example.com'
    Lux::Current.new("http://#{host}#{path}")
    Lux.current.nav
  end

  describe '#root' do
    it 'returns the first path segment' do
      _(nav_for('/users/123').root).must_equal 'users'
    end

    it 'returns nil for root path' do
      _(nav_for('/').root).must_be_nil
    end
  end

  describe '#root?' do
    it 'matches root segment by symbol' do
      _(nav_for('/admin/foo').root?(:admin)).must_equal true
    end

    it 'matches root segment by string' do
      _(nav_for('/admin/foo').root?('admin')).must_equal true
    end

    it 'returns false on mismatch' do
      _(nav_for('/admin/foo').root?(:users)).must_equal false
    end

    it 'returns false at root path' do
      _(nav_for('/').root?(:admin)).must_equal false
    end
  end

  describe '#child' do
    it 'returns the second path segment' do
      _(nav_for('/users/profile').child).must_equal 'profile'
    end

    it 'returns nil when no child' do
      _(nav_for('/users').child).must_be_nil
    end
  end

  describe '#last' do
    it 'returns the last path segment' do
      _(nav_for('/a/b/c').last).must_equal 'c'
    end
  end

  describe '#path' do
    it 'returns the path array' do
      nav = nav_for('/a/b/c')
      _(nav.path).must_equal %w[a b c]
    end

    it 'returns empty array for root' do
      nav = nav_for('/')
      _(nav.path).must_equal []
    end
  end

  describe '#to_s' do
    it 'joins path segments' do
      _(nav_for('/users/profile').to_s).must_equal 'users/profile'
    end
  end

  describe '#domain' do
    it 'extracts domain from standard host' do
      _(nav_for('/', host: 'www.example.com').domain).must_equal 'example.com'
    end

    it 'handles localhost' do
      _(nav_for('/', host: 'localhost').domain).must_equal 'localhost'
    end

    it 'handles IP addresses' do
      _(nav_for('/', host: '127.0.0.1').domain).must_equal '127.0.0.1'
    end

    it 'handles multi-part TLDs' do
      _(nav_for('/', host: 'app.foo.co.uk').domain).must_equal 'foo.co.uk'
    end
  end

  describe '#subdomain' do
    it 'extracts subdomain from host' do
      _(nav_for('/', host: 'admin.example.com').subdomain).must_equal 'admin'
    end

    it 'returns empty string when no subdomain' do
      _(nav_for('/', host: 'example.com').subdomain).must_equal ''
    end

    it 'handles multiple subdomains' do
      _(nav_for('/', host: 'a.b.example.com').subdomain).must_equal 'a.b'
    end
  end

  describe '#format' do
    it 'extracts file format from last path segment' do
      nav = nav_for('/api/data.json')
      _(nav.format).must_equal :json
    end

    it 'is nil when no format present' do
      nav = nav_for('/api/data')
      _(nav.format).must_be_nil
    end

    it 'strips format from the path segment' do
      nav = nav_for('/api/data.json')
      _(nav.last).must_equal 'data'
    end
  end

  describe '#pathname' do
    it 'returns clean path string' do
      nav = nav_for('/users/profile')
      _(nav.pathname).must_equal '/users/profile'
    end

    it 'checks path inclusion with has:' do
      nav = nav_for('/users/profile/edit')
      _(nav.pathname(has: 'profile')).must_equal true
      _(nav.pathname(has: 'missing')).must_equal false
    end

    it 'checks path ending with ends:' do
      nav = nav_for('/users/profile/edit')
      _(nav.pathname(ends: 'edit')).must_equal true
      _(nav.pathname(ends: 'profile')).must_equal false
    end
  end

  describe '#[]' do
    it 'accesses canonical path by index' do
      nav = nav_for('/a/b/c')
      _(nav[0]).must_equal 'a'
      _(nav[1]).must_equal 'b'
      _(nav[2]).must_equal 'c'
    end

    it 'reflects :ref rewrites from nav.ref' do
      nav = nav_for('/boards/abc-123/edit')
      nav.ref { |el| el.include?('-') ? el.split('-').last : nil }
      _(nav[1]).must_equal :ref
    end
  end

  describe '#ref capture' do
    it 'stores extracted refs in nav.refs and exposes first as nav.ref' do
      nav = nav_for('/boards/abc-123/edit')
      nav.ref { |el| el.include?('-') ? el.split('-').last : nil }
      _(nav.ref).must_equal '123'
      _(nav.refs).must_equal ['123']
    end

    it 'preserves spatial order across multiple refs' do
      nav = nav_for('/orgs/a-1/users/b-2')
      nav.ref { |el| el.include?('-') ? el.split('-').last : nil }
      _(nav.refs).must_equal ['1', '2']
      _(nav.ref).must_equal '1'
    end

    it 'is idempotent - existing :ref symbols are skipped on re-run' do
      nav = nav_for('/boards/abc-123')
      classifier = ->(el) { el.include?('-') ? el.split('-').last : nil }
      nav.ref(&classifier)
      _(nav.refs).must_equal ['123']

      # second call must not re-process the :ref symbol or push a duplicate
      nav.ref(&classifier)
      _(nav.refs).must_equal ['123']
      _(nav.path).must_equal ['boards', :ref]
    end

    it 'is a pure reader with no block - never mutates the path' do
      nav = nav_for('/boards/abc-123/edit')
      _(nav.ref).must_be_nil
      _(nav.path).must_equal %w[boards abc-123 edit]

      nav.ref { |el| el.include?('-') ? el.split('-').last : nil }
      before = nav.path.dup
      _(nav.ref).must_equal '123'
      _(nav.ref).must_equal '123'
      _(nav.path).must_equal before
    end

    it 'block form returns the same value the reader does' do
      nav = nav_for('/orgs/a-1/users/b-2')
      returned = nav.ref { |el| el.include?('-') ? el.split('-').last : nil }
      _(returned).must_equal nav.ref
      _(returned).must_equal '1'
    end

    it 'stores the segment itself when the block returns true' do
      nav = nav_for('/boards/abc123')
      nav.ref { |el| el == 'abc123' }
      _(nav.ref).must_equal 'abc123'
      _(nav.path).must_equal ['boards', :ref]
    end
  end

  describe '#source_path' do
    it 'is the path as it arrived, normalised but not rewritten' do
      nav = nav_for('/Boards/ABC-123/Edit')
      _(nav.source_path).must_equal %w[boards abc-123 edit]
    end

    it 'has the format already stripped' do
      nav = nav_for('/users/data.json')
      _(nav.source_path).must_equal %w[users data]
      _(nav.format).must_equal :json
    end

    it 'has key:value segments already popped into params' do
      nav = nav_for('/users/page:3')
      _(nav.source_path).must_equal %w[users]
      _(Lux.current.params[:page]).must_equal '3'
    end

    it 'survives nav.ref classification' do
      nav = nav_for('/boards/abc-123/edit')
      nav.ref { |el| el.include?('-') ? el.split('-').last : nil }
      _(nav.path).must_equal ['boards', :ref, 'edit']
      _(nav.source_path).must_equal %w[boards abc-123 edit]
    end

    it 'survives nav.locale peeling' do
      nav = nav_for('/en/users')
      nav.locale { |l| l.length == 2 ? l : nil }
      _(nav.path).must_equal %w[users]
      _(nav.source_path).must_equal %w[en users]
    end

    it 'survives app rewrites of nav.path' do
      nav = nav_for('/boards/ab/edit')
      nav.path[1] = 'full-ref'
      nav.path.unshift 'x'
      nav.path.map! { |el| el.tr('-', '_') }
      _(nav.source_path).must_equal %w[boards ab edit]
    end

    it 'is frozen' do
      _(nav_for('/a/b').source_path).must_be :frozen?
    end

    # plugins/pdf signs this string and re-verifies it on the follow-up request,
    # so it has to survive load_models rewriting the ref segment out of nav.path.
    it 'yields a stable pathname before and after classification' do
      nav      = nav_for('/pdf/salary-runs/abc123/obracun.pdf')
      pathname = -> { '/' + nav.source_path.join('/') }
      before   = pathname.call

      nav.ref { |el| el == 'abc123' ? el : nil }

      _(pathname.call).must_equal before
      _(before).must_equal '/pdf/salary-runs/abc123/obracun'   # format already stripped
    end
  end

  describe 'colon-param variables from path' do
    it 'extracts colon-separated params from path' do
      nav = nav_for('/users/page:3')
      _(Lux.current.params[:page]).must_equal '3'
    end
  end

  describe 'path lowercasing' do
    it 'lowercases path segments' do
      nav = nav_for('/Foo/Bar')
      _(nav.path).must_equal %w[foo bar]
    end

    it 'lowercases qs key but preserves qs value' do
      nav = nav_for('/Foo/BAR:BAZ')
      _(Lux.current.params[:bar]).must_equal 'BAZ'
      _(nav.path).must_equal %w[foo]
    end

    it 'only lowercases up to the first colon in a segment' do
      nav = nav_for('/A/Key:Val:Extra')
      _(Lux.current.params[:key]).must_equal 'Val:Extra'
      _(nav.path).must_equal %w[a]
    end
  end

  describe '#locale' do
    it 'extracts locale from first path segment' do
      nav = nav_for('/en/users')
      locale = nav.locale { |l| l.length == 2 ? l : nil }
      _(locale).must_equal 'en'
      _(nav.root).must_equal 'users'
    end

    it 'returns nil when locale filter rejects' do
      nav = nav_for('/users/profile')
      locale = nav.locale { |l| l.length == 2 ? l : nil }
      _(locale).must_be_nil
    end

    it 'is a reader with no block - does not raise on a locale-shaped path' do
      nav = nav_for('/en/users')
      _(nav.locale).must_be_nil
      _(nav.path).must_equal %w[en users]
    end

    it 'reads back the resolved locale with no block' do
      nav = nav_for('/en/users')
      nav.locale { |l| l.length == 2 ? l : nil }
      _(nav.locale).must_equal 'en'
    end
  end
end
