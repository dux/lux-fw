require 'test_helper'

describe Lux::Application::Route do
  def route_for path
    Lux::Current.new("http://example.com#{path}")
    Lux.current.route
  end

  describe '#path' do
    it 'returns the full nav path when no scope is entered' do
      _(route_for('/a/b/c').path).must_equal %w[a b c]
    end

    it 'returns the path slice after consumed offset' do
      route = route_for('/a/b/c')
      route.with_scope(1) do
        _(route.path).must_equal %w[b c]
      end
    end

    it 'supports nested scopes' do
      route = route_for('/a/b/c/d')
      route.with_scope(1) do
        route.with_scope(1) do
          _(route.path).must_equal %w[c d]
        end
      end
    end

    it 'unwinds offset on scope exit' do
      route = route_for('/a/b/c')
      route.with_scope(1) {}
      _(route.path).must_equal %w[a b c]
    end

    it 'unwinds offset even when block raises' do
      route = route_for('/a/b/c')
      _{ route.with_scope(1) { raise 'boom' } }.must_raise RuntimeError
      _(route.path).must_equal %w[a b c]
    end
  end

  describe '#root' do
    it 'returns the first remaining segment' do
      route = route_for('/a/b/c')
      _(route.root).must_equal 'a'
      route.with_scope(1) do
        _(route.root).must_equal 'b'
      end
    end

    it 'returns nil when fully consumed' do
      route = route_for('/a')
      route.with_scope(1) do
        _(route.root).must_be_nil
      end
    end
  end

  describe '#child' do
    it 'returns the second remaining segment' do
      route = route_for('/a/b/c')
      _(route.child).must_equal 'b'
      route.with_scope(1) do
        _(route.child).must_equal 'c'
      end
    end
  end

  describe '#consumed' do
    it 'returns segments before the cursor' do
      route = route_for('/a/b/c')
      _(route.consumed).must_equal []
      route.with_scope(1) do
        _(route.consumed).must_equal %w[a]
        route.with_scope(1) do
          _(route.consumed).must_equal %w[a b]
        end
      end
    end
  end

  describe 'nav.path is not mutated by route scoping' do
    it 'leaves nav.path intact across scopes' do
      Lux::Current.new('http://example.com/a/b/c')
      Lux.current.route.with_scope(1) do
        _(Lux.current.nav.path).must_equal %w[a b c]
      end
      _(Lux.current.nav.path).must_equal %w[a b c]
    end
  end

  describe '#match?' do
    it 'matches a String against the cursor root' do
      _(route_for('/admin/users').match?('admin')).must_equal true
      _(route_for('/admin/users').match?('users')).must_equal false
    end

    it 'strips a leading slash from the pattern' do
      _(route_for('/admin').match?('/admin')).must_equal true
    end

    it 'matches a Symbol' do
      _(route_for('/admin').match?(:admin)).must_equal true
    end

    it 'matches a Regexp against the raw segment' do
      _(route_for('/@dux').match?(%r{^@})).must_equal true
      _(route_for('/dux').match?(%r{^@})).must_equal false
    end

    it 'matches any member of an Array' do
      _(route_for('/b').match?([:a, :b])).must_equal true
      _(route_for('/c').match?([:a, :b])).must_equal false
    end

    it 'treats - and _ as the same character on both sides' do
      _(route_for('/cash-book').match?(:cash_book)).must_equal true
      _(route_for('/cash_book').match?('cash-book')).must_equal true
    end

    it 'is false at the end of the path' do
      route = route_for('/a')
      route.with_scope(1) { _(route.match?('a')).must_equal false }
    end

    it 'follows the cursor, not nav.path' do
      route = route_for('/admin/users')
      _(route.match?('users')).must_equal false
      route.with_scope(1) { _(route.match?('users')).must_equal true }
    end
  end

  describe '#start_with?' do
    it 'matches a single segment at the cursor' do
      _(route_for('/spaces/abc').start_with?(:spaces)).must_equal true
      _(route_for('/notes/abc').start_with?(:spaces)).must_equal false
    end

    it 'matches several segments in one step' do
      _(route_for('/admin/users/1').start_with?(:admin, :users)).must_equal true
      _(route_for('/admin/notes/1').start_with?(:admin, :users)).must_equal false
    end

    it 'normalizes dashes' do
      _(route_for('/cash-book-entries/1').start_with?(:cash_book_entries)).must_equal true
    end

    it 'matches the :ref placeholder after classification' do
      Lux::Current.new('http://example.com/spaces/abc123')
      Lux.current.nav.map_path { |el| el == 'abc123' ? el : nil }
      _(Lux.current.route.start_with?(:spaces, :ref)).must_equal true
    end

    it 'does not match :ref before classification has run' do
      _(route_for('/spaces/abc123').start_with?(:spaces, :ref)).must_equal false
    end

    # :ref is matched by type, so a segment literally spelled "ref" is not one
    it 'does not match a literal ref segment' do
      _(route_for('/spaces/ref').start_with?(:spaces, :ref)).must_equal false
    end

    it 'does not match a classified segment against its own text' do
      Lux::Current.new('http://example.com/spaces/abc123')
      Lux.current.nav.map_path { |el| el == 'abc123' ? el : nil }
      _(Lux.current.route.start_with?(:spaces, :abc123)).must_equal false
    end

    it 'is false with no segments given' do
      _(route_for('/a').start_with?).must_equal false
    end

    it 'is false when the path is shorter than the pattern' do
      _(route_for('/admin').start_with?(:admin, :users)).must_equal false
    end

    it 'follows the cursor' do
      route = route_for('/dev/settings')
      _(route.start_with?(:settings)).must_equal false
      route.with_scope(1) { _(route.start_with?(:settings)).must_equal true }
    end
  end

  describe '#normalized_path' do
    it 'is the cursor-relative view of Nav#normalized_path' do
      Lux::Current.new('http://example.com/admin/spaces/abc123/edit')
      Lux.current.nav.map_path { |el| el == 'abc123' ? el : nil }
      route = Lux.current.route

      _(route.normalized_path).must_equal %w[admin spaces ref edit]
      route.with_scope(1) { _(route.normalized_path).must_equal %w[spaces ref edit] }
    end
  end

  describe '#capture' do
    it 'returns an empty hash for a literal match' do
      _(route_for('/city/people').capture('/city/people')).must_equal({})
    end

    it 'returns nil when a literal segment differs' do
      _(route_for('/city/people').capture('/town/people')).must_be_nil
    end

    it 'binds :name placeholders' do
      _(route_for('/zagreb/people').capture('/:city/people')).must_equal({ city: 'zagreb' })
    end

    it 'matches from the URL root, not the cursor' do
      route = route_for('/a/b')
      route.with_scope(1) { _(route.capture('/a/b')).must_equal({}) }
    end

    it 'does not match when a placeholder has no segment to bind' do
      _(route_for('/users').capture('/users/:id')).must_be_nil
    end

    it 'binds the id, not the placeholder, when nav.ref classification already ran' do
      Lux::Current.new('http://example.com/users/abc123/dashboard')
      Lux.current.nav.map_path { |el| el == 'abc123' ? el : nil }
      _(Lux.current.nav.path[1]).must_be_kind_of Lux::Application::Nav::Base
      _(Lux.current.route.capture('/users/:ref/dashboard')).must_equal({ ref: 'abc123' })
    end

    # regression: the value used to be recovered by counting placeholders to the
    # left, so overwriting an earlier one shifted every capture after it
    it 'binds the right id after an app rewrote an earlier segment' do
      Lux::Current.new('http://example.com/a/r1/b/r2')
      Lux.current.nav.map_path { |el| el.start_with?('r') ? el : nil }
      Lux.current.nav.path[1] = 'plain'
      _(Lux.current.route.capture('/a/plain/b/:y')).must_equal({ y: 'r2' })
    end

    it 'binds the right id when several refs precede the capture' do
      Lux::Current.new('http://example.com/a/r1/b/r2')
      Lux.current.nav.map_path { |el| el.start_with?('r') ? el : nil }
      _(Lux.current.route.capture('/a/:x/b/:y')).must_equal({ x: 'r1', y: 'r2' })
    end

    it 'reports the segment count it consumes' do
      _(route_for('/a/b').capture_length('/:x/b')).must_equal 2
    end
  end
end
