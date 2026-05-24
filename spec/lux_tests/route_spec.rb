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
end
