require 'spec_helper'

describe Lux::Application::Route do
  def route_for path
    Lux::Current.new("http://example.com#{path}")
    Lux.current.route
  end

  describe '#path' do
    it 'returns the full nav path when no scope is entered' do
      expect(route_for('/a/b/c').path).to eq(%w[a b c])
    end

    it 'returns the path slice after consumed offset' do
      route = route_for('/a/b/c')
      route.with_scope(1) do
        expect(route.path).to eq(%w[b c])
      end
    end

    it 'supports nested scopes' do
      route = route_for('/a/b/c/d')
      route.with_scope(1) do
        route.with_scope(1) do
          expect(route.path).to eq(%w[c d])
        end
      end
    end

    it 'unwinds offset on scope exit' do
      route = route_for('/a/b/c')
      route.with_scope(1) {}
      expect(route.path).to eq(%w[a b c])
    end

    it 'unwinds offset even when block raises' do
      route = route_for('/a/b/c')
      expect { route.with_scope(1) { raise 'boom' } }.to raise_error('boom')
      expect(route.path).to eq(%w[a b c])
    end
  end

  describe '#root' do
    it 'returns the first remaining segment' do
      route = route_for('/a/b/c')
      expect(route.root).to eq('a')
      route.with_scope(1) do
        expect(route.root).to eq('b')
      end
    end

    it 'returns nil when fully consumed' do
      route = route_for('/a')
      route.with_scope(1) do
        expect(route.root).to be_nil
      end
    end
  end

  describe '#child' do
    it 'returns the second remaining segment' do
      route = route_for('/a/b/c')
      expect(route.child).to eq('b')
      route.with_scope(1) do
        expect(route.child).to eq('c')
      end
    end
  end

  describe '#consumed' do
    it 'returns segments before the cursor' do
      route = route_for('/a/b/c')
      expect(route.consumed).to eq([])
      route.with_scope(1) do
        expect(route.consumed).to eq(%w[a])
        route.with_scope(1) do
          expect(route.consumed).to eq(%w[a b])
        end
      end
    end
  end

  describe 'nav.path is not mutated by route scoping' do
    it 'leaves nav.path intact across scopes' do
      Lux::Current.new('http://example.com/a/b/c')
      Lux.current.route.with_scope(1) do
        expect(Lux.current.nav.path).to eq(%w[a b c])
      end
      expect(Lux.current.nav.path).to eq(%w[a b c])
    end
  end
end
