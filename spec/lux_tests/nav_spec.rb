require 'spec_helper'

describe Lux::Application::Nav do
  def nav_for path, host: 'example.com'
    Lux::Current.new("http://#{host}#{path}")
    Lux.current.nav
  end

  describe '#root' do
    it 'returns the first path segment' do
      expect(nav_for('/users/123').root).to eq('users')
    end

    it 'returns nil for root path' do
      expect(nav_for('/').root).to be_nil
    end
  end

  describe '#child' do
    it 'returns the second path segment' do
      expect(nav_for('/users/profile').child).to eq('profile')
    end

    it 'returns nil when no child' do
      expect(nav_for('/users').child).to be_nil
    end
  end

  describe '#last' do
    it 'returns the last path segment' do
      expect(nav_for('/a/b/c').last).to eq('c')
    end
  end

  describe '#shift / #unshift' do
    it 'shifts the first path element' do
      nav = nav_for('/users/profile')
      shifted = nav.shift
      expect(shifted).to eq('users')
      expect(nav.root).to eq('profile')
    end

    it 'unshifts a previously shifted element' do
      nav = nav_for('/users/profile')
      nav.shift
      nav.unshift
      expect(nav.root).to eq('users')
    end

    it 'unshifts a custom value' do
      nav = nav_for('/users')
      nav.unshift('admin')
      expect(nav.root).to eq('admin')
      expect(nav.child).to eq('users')
    end
  end

  describe '#path' do
    it 'returns the path array' do
      nav = nav_for('/a/b/c')
      expect(nav.path).to eq(%w[a b c])
    end

    it 'returns empty array for root' do
      nav = nav_for('/')
      expect(nav.path).to eq([])
    end
  end

  describe '#to_s' do
    it 'joins path segments' do
      expect(nav_for('/users/profile').to_s).to eq('users/profile')
    end
  end

  describe '#domain' do
    it 'extracts domain from standard host' do
      expect(nav_for('/', host: 'www.example.com').domain).to eq('example.com')
    end

    it 'handles localhost' do
      expect(nav_for('/', host: 'localhost').domain).to eq('localhost')
    end

    it 'handles IP addresses' do
      expect(nav_for('/', host: '127.0.0.1').domain).to eq('127.0.0.1')
    end

    it 'handles multi-part TLDs' do
      expect(nav_for('/', host: 'app.foo.co.uk').domain).to eq('foo.co.uk')
    end
  end

  describe '#subdomain' do
    it 'extracts subdomain from host' do
      expect(nav_for('/', host: 'admin.example.com').subdomain).to eq('admin')
    end

    it 'returns empty string when no subdomain' do
      expect(nav_for('/', host: 'example.com').subdomain).to eq('')
    end

    it 'handles multiple subdomains' do
      expect(nav_for('/', host: 'a.b.example.com').subdomain).to eq('a.b')
    end
  end

  describe '#format' do
    it 'extracts file format from last path segment' do
      nav = nav_for('/api/data.json')
      expect(nav.format).to eq(:json)
    end

    it 'is nil when no format present' do
      nav = nav_for('/api/data')
      expect(nav.format).to be_nil
    end

    it 'strips format from the path segment' do
      nav = nav_for('/api/data.json')
      expect(nav.last).to eq('data')
    end
  end

  describe '#original' do
    it 'preserves original path segments' do
      nav = nav_for('/a/b/c')
      nav.shift
      expect(nav.original).to eq(%w[a b c])
    end
  end

  describe '#pathname' do
    it 'returns clean path string' do
      nav = nav_for('/users/profile')
      expect(nav.pathname).to eq('/users/profile')
    end

    it 'checks path inclusion with has:' do
      nav = nav_for('/users/profile/edit')
      expect(nav.pathname(has: 'profile')).to be true
      expect(nav.pathname(has: 'missing')).to be false
    end

    it 'checks path ending with ends:' do
      nav = nav_for('/users/profile/edit')
      expect(nav.pathname(ends: 'edit')).to be true
      expect(nav.pathname(ends: 'profile')).to be false
    end
  end

  describe '#[]' do
    it 'accesses original path by index' do
      nav = nav_for('/a/b/c')
      expect(nav[0]).to eq('a')
      expect(nav[1]).to eq('b')
      expect(nav[2]).to eq('c')
    end
  end

  describe 'colon-param variables from path' do
    it 'extracts colon-separated params from path' do
      nav = nav_for('/users/page:3')
      expect(Lux.current.params[:page]).to eq('3')
    end
  end

  describe '#locale' do
    it 'extracts locale from first path segment' do
      nav = nav_for('/en/users')
      locale = nav.locale { |l| l.length == 2 ? l : nil }
      expect(locale).to eq('en')
      expect(nav.root).to eq('users')
    end

    it 'returns nil when locale filter rejects' do
      nav = nav_for('/users/profile')
      locale = nav.locale { |l| l.length == 2 ? l : nil }
      expect(locale).to be_nil
    end
  end
end
